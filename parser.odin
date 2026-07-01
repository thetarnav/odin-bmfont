package bmfont

import "core:mem"
import "core:encoding/xml"
import "core:strconv"
import "core:strings"
import "core:slice"

// A single glyph in a BMFont atlas.
Glyph :: struct {
	char:           rune,
	pos, size:      [2]i16, // position/size in the texture
	off:            [2]i16, // draw offset from cursor
	advance:        i16,    // how much to advance cursor after drawing
	page:           u8,     // texture page with character
	channel:        u8,     // texture channel with character (1=blue, 2=green, 4=red, 8=alpha, 15=all channels)
}

// The character-set encoding for the font page. `<info unicode="…">`
Charset :: enum {
	Unicode,  // 0 — standard Unicode codepoints
	Symbol,   // 1 — symbol font (e.g. Webdings)
	Japanese, // 2 — Shift-JIS
}

// `<info padding="top,right,bottom,left">`
Padding_Index :: enum {Top, Right, Bottom, Left}

Format :: enum {
	// Standard BMFont XML (.xml, .fnt), produced by virtually every exporter.
	// Check `./fonts/WhitePeaberry.xml` for example
	XML,
	// AngelCode's text format (.txt, .fnt) — one tag per line followed by `key=value` pairs.
	// Check `./fonts/WhitePeaberry.txt` for example
	Text,
}

// Properties from the BMFont `<info>` tag
Info :: struct {
	face:      string,
	charset:   string, // The name of the OEM charset used (when not unicode)
	unicode:   Charset,
	bold:      bool,
	italic:    bool,
	smooth:    bool,
	aa:        bool,
	size:      int,             // in points (informational; not used by the renderer)
	stretch_h: int,             // horizontal stretch percentage; 100 = no stretch
	padding:   [Padding_Index]int, // top/right/bottom/left padding baked into the atlas
	spacing:   [2]int,             // horizontal/vertical gap between glyphs/lines
}

// A parsed BMFont file
Font :: struct {
	using info:  Info,
	line_height: int,
	base:        int,
	scale:       [2]int,
	glyphs:      []Glyph, // sorted by `char`
	ranges:      []int,   // Run lengths of consecutive codepoints in `glyphs`
}

Error :: union #shared_nil {
	xml.Error,
	BMFont_Error,
}

BMFont_Error :: enum {
	None = 0,
	No_Elements,
	No_Root,
	Unknown_Encoding,
	Illegal_Character,
}

// Parse a BMFont file string. The `encoding` argument picks the wire format.
@require_results
load_bmfont :: proc(
	source:   string,
	encoding: Format,
	allocator := context.allocator,
) -> (font: Font, err: Error) {
	switch encoding {
	case .XML:  return load_bmfont_xml(source, allocator)
	case .Text: return load_bmfont_text(source, allocator)
	}
	return {}, .Unknown_Encoding
}

// XML: full BMFont format produced by every exporter.
// `<font><info/><common/><pages/><chars/></font>`.
@require_results
load_bmfont_xml :: proc(source: string, allocator := context.allocator) -> (font: Font, err: Error) {

	doc := xml.parse(string(source), {flags = {.Ignore_Unsupported}}, allocator=context.temp_allocator) or_return

	if len(doc.elements) == 0 {
		return {}, .No_Elements
	}

	font_id: xml.Element_ID
	if doc.elements[0].ident == "font" {
		font_id = 0
	} else if id, found := xml.find_child_by_ident(doc, 0, "font"); found {
		font_id = id
	} else {
		return {}, .No_Root
	}

	glyphs := make([dynamic]Glyph, allocator)
	defer shrink(&glyphs)

	for v in doc.elements[font_id].value {
		child_id := v.(xml.Element_ID) or_continue
		tag := doc.elements[child_id]

		switch tag.ident {
		case "info":
			for attr in tag.attribs {
				set_info_kv(&font, attr.key, attr.val, allocator)
			}
		case "common":
			for attr in tag.attribs {
				set_common_kv(&font, attr.key, attr.val)
			}
		case "chars":
			for c in tag.value {
				char_id := c.(xml.Element_ID) or_continue
				char := doc.elements[char_id]
				if char.ident != "char" do continue

				g: Glyph
				for attr in char.attribs {
					set_char_kv(&g, attr.key, attr.val)
				}

				if g.char != 0 {
					append(&glyphs, g)
				}
			}
		}
	}

	font_set_glyphs(&font, glyphs[:], allocator)

	return
}

// AngelCode's text format. One tag per line, followed by `key=value` pairs
// separated by whitespace. Values can be quoted strings or bare numbers.
@require_results
load_bmfont_text :: proc (source: string, allocator := context.allocator) -> (font: Font, err: Error) {

	glyphs := make([dynamic]Glyph, 0, allocator)

	source := source
	for line in strings.split_lines_iterator(&source) {
		if len(line) == 0 do continue

		// First whitespace-separated word is the tag, the rest is the attr list
		tag, after_tag := line, ""
		if space_idx := strings.index(line, " "); space_idx != -1 {
			tag, after_tag = line[:space_idx], line[space_idx+1:]
		}

		switch tag {
		case "info":
			for input := after_tag; len(input) > 0; /**/ {
				key, val, rest := parse_text_kv(input) or_break
				set_info_kv(&font, key, val, allocator)
				input = rest
			}
		case "common":
			for input := after_tag; len(input) > 0; /**/ {
				key, val, rest := parse_text_kv(input) or_break
				set_common_kv(&font, key, val)
				input = rest
			}
		case "page", "chars", "kernings":
			// page: just `id=0 file="X.png"` — we don't need the page file
			// chars:  just `count=N` — we count via the actual `char` lines
			// kernings: ignored (BMFont kerning tables aren't part of `Font`)
		case "char":
			g: Glyph
			for input := after_tag; len(input) > 0; /**/ {
				key, val, rest := parse_text_kv(input) or_break
				set_char_kv(&g, key, val)
				input = rest
			}
			if g.char != 0 {
				append(&glyphs, g)
			}
		}
	}

	font_set_glyphs(&font, glyphs[:], allocator)

	return font, nil
}

@private
set_info_kv :: proc (font: ^Font, key, val: string, allocator: mem.Allocator) {
	switch key {
	case "face":     font.face      = strings.clone(val, allocator)
	case "size":     font.size      = strconv.parse_int(val) or_else 0
	case "bold":     font.bold      = (strconv.parse_int(val) or_else 0) != 0
	case "italic":   font.italic    = (strconv.parse_int(val) or_else 0) != 0
	case "charset":  font.charset   = strings.clone(val, allocator)
	case "unicode":  font.unicode   = Charset(strconv.parse_int(val) or_else 0)
	case "stretchH": font.stretch_h = strconv.parse_int(val) or_else 100
	case "smooth":   font.smooth    = (strconv.parse_int(val) or_else 0) != 0
	case "aa":       font.aa        = (strconv.parse_int(val) or_else 0) != 0
	case "padding":  font.padding   = parse_int_list(val, [Padding_Index]int) or_else {}
	case "spacing":  font.spacing   = parse_int_list(val, [2]int) or_else {}
	}
}

@private
set_common_kv :: proc (font: ^Font, key, val: string) {
	switch key {
	case "lineHeight": font.line_height = strconv.parse_int(val) or_else 0
	case "base":       font.base        = strconv.parse_int(val) or_else 0
	case "scaleW":     font.scale.x     = strconv.parse_int(val) or_else 0
	case "scaleH":     font.scale.y     = strconv.parse_int(val) or_else 0
	}
}

@private
set_char_kv :: proc (g: ^Glyph, key, val: string) {
	switch key {
	case "id":       g.char    = rune(strconv.parse_uint(val) or_else 0)
	case "x":        g.pos.x   = i16(strconv.parse_int(val) or_else 0)
	case "y":        g.pos.y   = i16(strconv.parse_int(val) or_else 0)
	case "width":    g.size.x  = i16(strconv.parse_int(val) or_else 0)
	case "height":   g.size.y  = i16(strconv.parse_int(val) or_else 0)
	case "xoffset":  g.off.x   = i16(strconv.parse_int(val) or_else 0)
	case "yoffset":  g.off.y   = i16(strconv.parse_int(val) or_else 0)
	case "xadvance": g.advance = i16(strconv.parse_int(val) or_else 0)
	case "page":     g.page    = u8(strconv.parse_uint(val) or_else 0)
	case "chnl":     g.channel = u8(strconv.parse_uint(val) or_else 0)
	}
}

// Parse one `key=value` pair from `s`. Values are either `"…"` (quoted, no escapes
// supported) or a bare run of non-whitespace. Returns the key, value, and the rest
// of the string after the pair (including any trailing whitespace).
@private
parse_text_kv :: proc(s: string) -> (key, val, rest: string, ok: bool) {

	// Skip leading whitespace.
	i := 0
	for i < len(s) && (s[i] == ' ' || s[i] == '\t') do i += 1
	if i >= len(s) do return

	// Key: up to the first '='.
	key_start := i
	for i < len(s) && s[i] != '=' do i += 1
	if i >= len(s) do return
	key = s[key_start:i]
	i += 1 // skip '='

	// Value: quoted string or bare token.
	if i < len(s) && s[i] == '"' {
		i += 1
		val_start := i
		for i < len(s) && s[i] != '"' do i += 1
		if i >= len(s) do return
		val = s[val_start:i]
		i += 1 // skip closing quote
	} else {
		val_start := i
		for i < len(s) && s[i] != ' ' && s[i] != '\t' do i += 1
		val = s[val_start:i]
	}

	return key, val, s[i:], true
}

// Parse a comma-separated integer list like "0,0,0,0" or "2,2" into a fixed-size array.
@(private, require_results)
parse_int_list :: proc(str: string, $T: typeid) -> (out: T, ok: bool) {
	written := 0
	it := str
	for p in strings.split_iterator(&it, ",") {
		if written >= len(out) do break
		v := strconv.parse_int(strings.trim_space(p)) or_continue
		out[auto_cast written] = v
		written += 1
	}
	return out, written > 0
}

@private
font_set_glyphs :: proc (font: ^Font, glyphs: []Glyph, allocator: mem.Allocator) {

	if len(glyphs) == 0 do return

	// glyphs should be sorted by the codepoint
	slice.sort_by(glyphs, proc (a, b: Glyph) -> bool {return a.char < b.char})
	font.glyphs = glyphs

	// build glyph ranges for consecutive codepoints
	ranges := make([dynamic]int, 0, allocator)
	run_len: int = 1
	for i in 1..<len(glyphs) {
		if glyphs[i].char == glyphs[i-1].char + 1 {
			run_len += 1
		} else {
			append(&ranges, run_len)
			run_len = 1
		}
	}
	append(&ranges, run_len)
	font.ranges = ranges[:]
}

// Returns the glyph and true on success, or a zero glyph and false if not found.
@require_results
find_glyph :: proc(font: Font, ch: rune) -> (g: Glyph, ok: bool) {
	offset: int
	for range in font.ranges {
		char := font.glyphs[offset].char
		if ch < char || ch >= char + rune(range) {
			offset += range
			continue
		}
		return font.glyphs[offset + int(ch-char)], true
	}
	return
}
get_glyph :: find_glyph

destroy_font :: proc (font: Font, allocator := context.allocator, loc := #caller_location) -> mem.Allocator_Error {
	delete(font.glyphs, allocator, loc=loc) or_return
	return delete(font.ranges, allocator, loc=loc)
}
