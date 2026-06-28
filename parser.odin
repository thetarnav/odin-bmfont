package bmfont

import "core:encoding/xml"
import "core:strconv"
import "core:slice"

// A single glyph in a BMFont atlas. Coordinates are in source pixels.
Font_Glyph :: struct {
	char:           rune,
	pos, size, off: [2]i16,
	advance:        i16,
	page, channel:  u8,
}

// A bitmap font parsed from a BMFont XML file
Font :: struct {
	face:        string,
	line_height: int,
	base:        int,
	scale:       [2]int,
	glyphs:      []Font_Glyph, // sorted codepoint -> glyph
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

	glyphs := make([dynamic]Font_Glyph, allocator)
	defer shrink(&glyphs)

	for v in doc.elements[font_id].value {
		child_id := v.(xml.Element_ID) or_continue
		tag := doc.elements[child_id]

		switch tag.ident {
		case "info":
			for attr in tag.attribs {
				if attr.key == "face" {
					font.face = attr.val
					break
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

				g: Font_Glyph

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

	foo :: proc () {
		return
	}

	slice.sort_by(glyphs[:], proc (a, b: Font_Glyph) -> bool {return a.char < b.char})
	font.glyphs = glyphs[:]

	return
}

destroy_font :: proc (font: Font, allocator := context.allocator, loc := #caller_location) {
	delete(font.glyphs, allocator, loc=loc)
}
