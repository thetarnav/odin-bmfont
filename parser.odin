// BMFont parser. Supports the original XML format and the AngelCode text format
// (`.txt` and its historical `.fnt` alias). All three produce the same `Font`
// value.
//
// The monogram-bitmap.json format (a flat per-character bitmap dictionary, no
// separate atlas image) lives in a separate loader under
// `example/load_json_font.odin` because it carries its own pixel data instead
// of atlas coordinates.

package bmfont

import "core:mem"
import "core:encoding/xml"
import "core:encoding/json"
import "core:strconv"
import "core:strings"
import "core:slice"

// A single glyph in a BMFont atlas. Coordinates are in source pixels.
Glyph :: struct {
	char:           rune,
	pos, size, off: [2]i16,
	advance:        i16,
	page, channel:  u8,
}

// The character-set encoding for the font page. `<info unicode="…">`
Charset :: enum {
	Unicode,  // 0 — standard Unicode codepoints
	Symbol,   // 1 — symbol font (e.g. Webdings)
	Japanese, // 2 — Shift-JIS
}

// `<info padding="top,right,bottom,left">`
Padding_Index :: enum {Top, Right, Bottom, Left}

Encoding :: enum {
	XML,  // Standard BMFont XML, produced by virtually every exporter.
	TXT,  // AngelCode's text format — one tag per line followed by `key=value` pairs.
	FNT,  // Historical alias for the AngelCode text format. Parsed identically to `.txt`.
}

// Properties from the BMFont `<info>` tag.
Info :: struct {
	face:      string,
	charset:   string,
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

// A bitmap font parsed from a BMFont file (any supported encoding).
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

// Parse a BMFont file from raw bytes. The `encoding` argument picks the wire format.
@require_results
load_font_from_bytes :: proc(
	bytes:    []byte,
	encoding: Encoding,
	allocator := context.allocator,
) -> (font: Font, err: Error) {
	switch encoding {
	case .XML:
		return load_font_from_xml(bytes, allocator)
	case .TXT, .FNT:
		return load_font_from_text(bytes, allocator)
	}
	return {}, .Unknown_Encoding
}

// XML: full BMFont format produced by every exporter. `<font><info/><common/><pages/><chars/></font>`.
@(private, require_results)
load_font_from_xml :: proc(bytes: []byte, allocator: mem.Allocator) -> (font: Font, err: Error) {
	doc := xml.parse(bytes, {flags = {.Ignore_Unsupported}}, allocator=context.temp_allocator) or_return

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
				switch attr.key {
				case "face":     font.face      = strings.clone(attr.val, allocator)
				case "size":     font.size      = strconv.parse_int(attr.val) or_else 0
				case "bold":     font.bold      = (strconv.parse_int(attr.val) or_else 0) != 0
				case "italic":   font.italic    = (strconv.parse_int(attr.val) or_else 0) != 0
				case "charset":  font.charset   = strings.clone(attr.val, allocator)
				case "unicode":  font.unicode   = Charset(strconv.parse_int(attr.val) or_else 0)
				case "stretchH": font.stretch_h = strconv.parse_int(attr.val) or_else 100
				case "smooth":   font.smooth    = (strconv.parse_int(attr.val) or_else 0) != 0
				case "aa":       font.aa        = (strconv.parse_int(attr.val) or_else 0) != 0
				case "padding":  font.padding   = parse_int_list(attr.val, [Padding_Index]int) or_else {}
				case "spacing":  font.spacing   = parse_int_list(attr.val, [2]int) or_else {}
				}
			}
		case "common":
			for attr in tag.attribs {
				switch attr.key {
				case "lineHeight": font.line_height = strconv.parse_int(attr.val) or_else 0
				case "base":       font.base        = strconv.parse_int(attr.val) or_else 0
				case "scaleW":     font.scale.x     = strconv.parse_int(attr.val) or_else 0
				case "scaleH":     font.scale.y     = strconv.parse_int(attr.val) or_else 0
				}
			}
		case "chars":
			chars: for c in tag.value {
				char_id := c.(xml.Element_ID) or_continue
				char := doc.elements[char_id]
				if char.ident != "char" do continue

				g: Glyph

				for attr in char.attribs {
					switch attr.key {
					case "id":       g.char    = rune(strconv.parse_uint(attr.val) or_continue chars)
					case "x":        g.pos.x   = i16(strconv.parse_int(attr.val) or_else 0)
					case "y":        g.pos.y   = i16(strconv.parse_int(attr.val) or_else 0)
					case "width":    g.size.x  = i16(strconv.parse_int(attr.val) or_else 0)
					case "height":   g.size.y  = i16(strconv.parse_int(attr.val) or_else 0)
					case "xoffset":  g.off.x   = i16(strconv.parse_int(attr.val) or_else 0)
					case "yoffset":  g.off.y   = i16(strconv.parse_int(attr.val) or_else 0)
					case "xadvance": g.advance = i16(strconv.parse_int(attr.val) or_else 0)
					case "page":     g.page    = u8(strconv.parse_uint(attr.val) or_else 0)
					case "chnl":     g.channel = u8(strconv.parse_uint(attr.val) or_else 0)
					}
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

// TXT / FNT: AngelCode's text format. One tag per line, followed by `key=value` pairs
// separated by whitespace. Values can be quoted strings or bare numbers. Each format
// is the same on-disk syntax; we only treat them as separate `Encoding` values so
// callers can be explicit.
@(private, require_results)
load_font_from_text :: proc(bytes: []byte, allocator: mem.Allocator) -> (font: Font, err: Error) {
	// The split lines, the per-line kv maps and any other scratch state all use the
	// temp allocator — no manual cleanup needed; the XML parser follows the same
	// pattern.
	text := string(bytes)
	lines := strings.split(text, "\n", context.temp_allocator)

	glyphs := make([dynamic]Glyph, 0, allocator)

	for line in lines {
		if len(line) == 0 do continue

		// First whitespace-separated word is the tag, the rest is the attr list.
		space_idx := strings.index(line, " ")
		tag:     string
		rest:    string
		if space_idx == -1 {
			tag  = line
			rest = ""
		} else {
			tag  = line[:space_idx]
			rest = line[space_idx + 1:]
		}

		switch tag {
		case "info":
			parse_text_info(rest, &font, allocator)
		case "common":
			parse_text_common(rest, &font)
		case "page", "chars", "kernings":
			// page: just `id=0 file="X.png"` — we don't need the page file
			// chars:  just `count=N` — we count via the actual `char` lines
			// kernings: ignored (BMFont kerning tables aren't part of `Font`)
		case "char":
			g, ok := parse_text_char(rest)
			if ok do append(&glyphs, g)
		}
	}

	font_set_glyphs(&font, glyphs[:], allocator)

	return font, nil
}

// ----------------------------------------------------------------------
// Text-format helpers
// ----------------------------------------------------------------------

parse_text_info :: proc(s: string, font: ^Font, allocator: mem.Allocator) {
	input := s
	for len(input) > 0 {
		key, val, rest, ok := parse_text_kv(input)
		if !ok do break
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
		input = rest
	}
}

parse_text_common :: proc(s: string, font: ^Font) {
	input := s
	for len(input) > 0 {
		key, val, rest, ok := parse_text_kv(input)
		if !ok do break
		switch key {
		case "lineHeight": font.line_height = strconv.parse_int(val) or_else 0
		case "base":       font.base        = strconv.parse_int(val) or_else 0
		case "scaleW":     font.scale.x     = strconv.parse_int(val) or_else 0
		case "scaleH":     font.scale.y     = strconv.parse_int(val) or_else 0
		}
		input = rest
	}
}

parse_text_char :: proc(s: string) -> (g: Glyph, ok: bool) {
	// `char id=32 x=20 ... letter="space"`
	seen := make(map[string]string, context.temp_allocator)
	defer delete(seen)

	input := s
	for len(input) > 0 {
		key, val, rest, kv_ok := parse_text_kv(input)
		if !kv_ok do break
		seen[key] = val
		input = rest
	}

	id_str, has_id := seen["id"]
	if !has_id do return
	id, id_ok := strconv.parse_int(id_str)
	if !id_ok do return

	g.char = rune(id)
	if g.char == 0 do return

	if v, has := seen["x"];        has do g.pos.x  = i16(strconv.parse_int(v) or_else 0)
	if v, has := seen["y"];        has do g.pos.y  = i16(strconv.parse_int(v) or_else 0)
	if v, has := seen["width"];    has do g.size.x = i16(strconv.parse_int(v) or_else 0)
	if v, has := seen["height"];   has do g.size.y = i16(strconv.parse_int(v) or_else 0)
	if v, has := seen["xoffset"];  has do g.off.x  = i16(strconv.parse_int(v) or_else 0)
	if v, has := seen["yoffset"];  has do g.off.y  = i16(strconv.parse_int(v) or_else 0)
	if v, has := seen["xadvance"]; has do g.advance = i16(strconv.parse_int(v) or_else 0)
	if v, has := seen["page"];     has do g.page    = u8(strconv.parse_uint(v) or_else 0)
	if v, has := seen["chnl"];     has do g.channel = u8(strconv.parse_uint(v) or_else 0)

	return g, true
}

// Parse one `key=value` pair from `s`. Values are either `"…"` (quoted, no escapes
// supported) or a bare run of non-whitespace. Returns the key, value, and the rest
// of the string after the pair (including any trailing whitespace).
parse_text_kv :: proc(s: string) -> (key, val, rest: string, ok: bool) {
	// Skip leading whitespace.
	i := 0
	for i < len(s) && (s[i] == ' ' || s[i] == '\t') do i += 1
	if i >= len(s) do return "", "", "", false

	// Key: up to the first '='.
	key_start := i
	for i < len(s) && s[i] != '=' do i += 1
	if i >= len(s) do return "", "", "", false
	key = s[key_start:i]
	i += 1 // skip '='

	// Value: quoted string or bare token.
	if i < len(s) && s[i] == '"' {
		i += 1
		val_start := i
		for i < len(s) && s[i] != '"' do i += 1
		if i >= len(s) do return "", "", "", false
		val = s[val_start:i]
		i += 1 // skip closing quote
	} else {
		val_start := i
		for i < len(s) && s[i] != ' ' && s[i] != '\t' do i += 1
		val = s[val_start:i]
	}

	return key, val, s[i:], true
}

// ----------------------------------------------------------------------
// Common helpers
// ----------------------------------------------------------------------

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
