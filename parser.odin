package bmfont

import "core:mem"
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

// The character-set encoding for the font page. `<info unicode="…">`
Charset :: enum {
	Unicode,  // 0 — standard Unicode codepoints
	Symbol,   // 1 — symbol font (e.g. Webdings)
	Japanese, // 2 — Shift-JIS
}

// `<info padding="top,right,bottom,left">`
Padding_Index :: enum {Top, Right, Bottom, Left}

// Properties from the BMFont `<info>` tag.
Info :: struct {
	face:      string,
	charset:   string,
	unicode:   Charset,
	bold:      bool,
	italic:    bool,
	smooth:    bool,
	aa:        bool,
	size:      int,         // in points (informational; not used by the renderer)
	stretch_h: int,         // horizontal stretch percentage; 100 = no stretch
	padding:   [Padding_Index]int, // top/right/bottom/left padding baked into the atlas
	spacing:   [2]int,             // horizontal/vertical gap between glyphs/lines
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

@require_results
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

	slice.sort_by(glyphs[:], proc (a, b: Glyph) -> bool {return a.char < b.char})
	font.glyphs = glyphs[:]

	return
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

// Find a glyph by codepoint using binary search. Glyphs are sorted by char at load time.
// Returns the glyph and true on success, or a zero glyph and false if not found.
@require_results
find_glyph :: proc(font: Font, ch: rune) -> (g: Glyph, ok: bool) {
	idx := slice.binary_search_by(font.glyphs, ch, proc (g: Glyph, ch: rune) -> slice.Ordering {
		return g.char < ch ? .Less : .Greater
	}) or_return
	return font.glyphs[idx], true
}
get_glyph :: find_glyph

destroy_font :: proc (font: Font, allocator := context.allocator, loc := #caller_location) -> mem.Allocator_Error {
	return delete(font.glyphs, allocator, loc=loc)
}
