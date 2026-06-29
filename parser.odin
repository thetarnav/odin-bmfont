package bmfont

import "core:encoding/xml"
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

// The character-set encoding for the font page. The BMFont `<info unicode="…">` attribute.
Charset :: enum {
	Unicode,  // 0 — standard Unicode codepoints
	Symbol,   // 1 — symbol font (e.g. Webdings)
	Japanese, // 2 — Shift-JIS
}

// Index into the BMFont `<info padding="top,right,bottom,left">` array.
Padding_Index :: enum {
	top,
	right,
	bottom,
	left,
}

// Index into the BMFont `<info spacing="horizontal,vertical">` array.
Spacing_Index :: enum {
	horizontal,
	vertical,
}

// Properties from the BMFont `<info>` tag. The simple BMFonts shipped with this project
// only set `face`/`size`/`bold`/`italic`; full BMFont exports (e.g. Glyph Designer)
// also include `charset`, `unicode`, `stretchH`, `smooth`, `aa`, `padding` and `spacing`.
// Fields default to zero/empty/false when the corresponding attribute is absent.
Info :: struct {
	face:      string,
	size:      int,         // in points (informational; not used by the renderer)
	bold:      bool,
	italic:    bool,
	charset:   string,
	unicode:   Charset,
	stretch_h: int,         // horizontal stretch percentage; 100 = no stretch
	smooth:    bool,
	aa:        bool,
	padding:   [Padding_Index]int, // top/right/bottom/left padding baked into the atlas
	spacing:   [Spacing_Index]int, // horizontal/vertical gap between glyphs/lines
}

// A bitmap font parsed from a BMFont XML file
Font :: struct {
	using info:  Info,
	line_height: int,
	base:        int,
	scale:       [2]int,
	glyphs:      []Glyph, // sorted codepoint -> glyph
}

Error :: union #shared_nil {
	xml.Error,
	BMFont_Error,
}

BMFont_Error :: enum {
	None = 0,
	No_Elements,
	No_Root,
}

load_font_from_bytes :: proc (bytes: []byte, allocator := context.allocator) -> (font: Font, err: Error) {

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
				case "face":      font.face      = attr.val
				case "size":      font.size      = strconv.parse_int(attr.val) or_else 0
				case "bold":      font.bold      = (strconv.parse_int(attr.val) or_else 0) != 0
				case "italic":    font.italic    = (strconv.parse_int(attr.val) or_else 0) != 0
				case "charset":   font.charset   = attr.val
				case "unicode":   font.unicode   = Charset(strconv.parse_int(attr.val) or_else 0)
				case "stretchH":  font.stretch_h = strconv.parse_int(attr.val) or_else 100
				case "smooth":    font.smooth    = (strconv.parse_int(attr.val) or_else 0) != 0
				case "aa":        font.aa        = (strconv.parse_int(attr.val) or_else 0) != 0
				case "padding":
					if v, ok := parse_padding(attr.val); ok {
						font.padding = v
					}
				case "spacing":
					if v, ok := parse_spacing(attr.val); ok {
						font.spacing = v
					}
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

	slice.sort_by(glyphs[:], proc (a, b: Glyph) -> bool {return a.char < b.char})
	font.glyphs = glyphs[:]

	return
}

// Parse a comma-separated integer list like "0,0,0,0" or "2,2" into a fixed-size array.
// Trailing/empty parts and out-of-range counts are ignored. Returns `ok=false` if the
// string has zero numeric parts. The scratch buffer from `strings.split` uses the temp
// allocator so it is freed automatically at the end of the frame.
parse_int_list :: proc(s: string, $N: int) -> (out: [N]int, ok: bool) {
	if len(s) == 0 do return
	parts, _ := strings.split(s, ",", context.temp_allocator)

	written := 0
	for p in parts {
		if written >= N do break
		v := strconv.parse_int(strings.trim_space(p)) or_continue
		out[written] = v
		written += 1
	}
	return out, written > 0
}

// Parse the BMFont `<info padding="top,right,bottom,left">` attribute into a named array.
parse_padding :: proc(s: string) -> (out: [Padding_Index]int, ok: bool) {
	raw := parse_int_list(s, 4) or_return
	return {
		.top    = raw[0],
		.right  = raw[1],
		.bottom = raw[2],
		.left   = raw[3],
	}, true
}

// Parse the BMFont `<info spacing="horizontal,vertical">` attribute into a named array.
parse_spacing :: proc(s: string) -> (out: [Spacing_Index]int, ok: bool) {
	raw := parse_int_list(s, 2) or_return
	return {
		.horizontal = raw[0],
		.vertical   = raw[1],
	}, true
}

// Find a glyph by codepoint using binary search. Glyphs are sorted by char at load time.
// Returns the glyph and true on success, or a zero glyph and false if not found.
find_glyph :: proc(font: Font, ch: rune) -> (g: Glyph, ok: bool) {
	idx := slice.binary_search_by(font.glyphs, ch, proc (g: Glyph, ch: rune) -> slice.Ordering {
		return g.char < ch ? .Less : .Greater
	}) or_return
	return font.glyphs[idx], true
}
get_glyph :: find_glyph

destroy_font :: proc (font: Font, allocator := context.allocator, loc := #caller_location) {
	delete(font.glyphs, allocator, loc=loc)
}
