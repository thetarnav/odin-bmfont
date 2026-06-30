package bmfont

import "core:math/linalg"
import "core:unicode"

RGBA :: [4]u8

Atlas :: struct {
	pixels: []RGBA,
	size:   [2]int,
}

// Load a font from a JSON byte stream. The returned `font` has its glyph metadata
// (pos/size/off/advance) computed from the row bitmaps; the returned `atlas` has
// the raw RGBA8 pixel data the caller uploads as a texture.
@require_results
load_font_from_json_bytes :: proc(
	bytes:    []byte,
	include_chars: map[rune]struct {} = nil,
	allocator := context.allocator,
) -> (font: Font, atlas: Atlas, err: Error) {

	SPACE_W       :: 4
	ATLAS_CHARS_H :: 10
	ATLAS_GAP     :: 1

	State :: enum {
		Brace_Open,  // {
		Quote_Open,  // "...
		Char,        // rune
		Char_Escape, // \rune
		Quote_Close, // ..."
		Colon,       // :
		Array,       // [...
		Int_1,       // 9
		Int_2,       // 99
		After_Int,   // 9, | 9]
		Comma,       // ],
	}
	state_char := #partial [State]rune{
		.Brace_Open  = '{',
		.Quote_Open  = '"',
		.Quote_Close = '"',
		.Colon       = ':',
		.Array       = '[',
	}

	state: State
	buf := make([dynamic]byte, context.temp_allocator)
	char: rune
	buf_off: int
	size_max: [2]int
	line_height: int
	Char :: struct {char: rune, buf: []byte, s, e: [2]int}
	chars := make([dynamic]Char, context.temp_allocator)

	parse: for c in string(bytes) {
		switch state {
		case .Brace_Open,
		     .Quote_Open,
		     .Quote_Close,
		     .Colon,
		     .Array:
			if unicode.is_white_space(c) do continue
			if c != state_char[state] {
				return {}, {}, .Illegal_Character
			}
		case .Char:
			if c == '"' do return {}, {}, .Illegal_Character
			char = c
		case .Char_Escape:
			if char == '\\' {
				char = c
			} else if c == '"' {
				state = .Colon
				continue
			} else {
				return {}, {}, .Illegal_Character
			}
		case .Int_1:
			if unicode.is_white_space(c) do continue
			append_nothing(&buf)
			state = .Int_2
			fallthrough
		case .Int_2:
			#no_bounds_check if c >= '0' && c <= '9' {
				buf[len(buf)-1] = (buf[len(buf)-1] * 10) + u8(c - '0')
				continue
			}
			else if unicode.is_white_space(c) do break
			state = .After_Int
			fallthrough
		case .After_Int:
			if unicode.is_white_space(c) do continue
			switch c {
			case ',':
				state = .Int_1
				continue
			case ']':
				if include_chars == nil || char in include_chars {
					s := [2]int{8, 8}
					e := [2]int{0, 0}
					for row, ri in buf[buf_off:] {
						for bi in 0..<8 {
							if row & (1 << u8(bi)) != 0 {
								s.x = min(s.x, bi)
								e.x = max(e.x, bi+1)
							}
						}
						if row > 0 {
							s.y = min(s.y, ri)
							e.y = max(e.y, ri+1)
						}
					}
					e = linalg.max(s, e)
					size_max = linalg.max(e-s, size_max)
					line_height = max(len(buf)-buf_off, line_height)
					append(&chars, Char{char, buf[buf_off:], s, e})
					buf_off = len(buf)
				} else {
					resize(&buf, buf_off)
				}
			case:
				return {}, {}, .Illegal_Character
			}
		case .Comma:
			if unicode.is_white_space(c) do continue
			switch c {
			case ',': // next state - next char
			case '}': break parse
			case: return {}, {}, .Illegal_Character
			}
		}

		state = max(State((int(state) + 1) % len(State)), State.Quote_Open)
	}

	cols := min(len(chars), ATLAS_CHARS_H)
	rows := len(chars) / cols
	if rows * cols < len(chars) {
		rows += 1
	}

	gap := ATLAS_GAP
	atlas.size   = [2]int{cols, rows} * (size_max + gap) + gap
	atlas.pixels = make([]RGBA, atlas.size.x * atlas.size.y, allocator)

	glyphs := make([]Glyph, len(chars), allocator)

	for c, ci in chars {
		x := (ci % cols) * (size_max.x + gap) + gap
		y := (ci / cols) * (size_max.y + gap) + gap
		size := c.e-c.s
		off  := c.s
		for row, ri in c.buf[off.y:c.e.y] {
			for bi in off.x ..< c.e.x {
				atlas.pixels[(y + ri) * atlas.size.x + x + bi - off.x] = (row & (1 << u8(bi))) * 255
			}
		}
		glyphs[ci] = {
			char    = c.char,
			pos     = {i16(x), i16(y)},
			size    = ([2]i16)(size),
			off     = ([2]i16)(off),
			advance = i16(size.x) if size.x > 0 else SPACE_W,
		}
	}

	font.face        = ""
	font.line_height = line_height
	font.base        = size_max.y
	font.padding     = {}
	font.spacing     = {1, 1}

	font_set_glyphs(&font, glyphs, allocator)

	return
}
