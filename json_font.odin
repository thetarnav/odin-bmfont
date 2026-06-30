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
load_font_from_json_bytes :: proc (
	bytes:   []byte,
	include: string = {},
	space_width := 4,
	atlas_cols  := 10,
	atlas_gap   := 1,
	allocator   := context.allocator,
) -> (font: Font, atlas: Atlas, err: Error) {

	charset := make(map[rune]struct {}, context.temp_allocator)
	for c in include do charset[c] = {}

	State :: enum {
		Brace_Open,  // {
		Quote_Open,  // "...
		Char,        // rune
		Quote_Close, // ..."
		Colon,       // :
		Array,       // [...
		Int_1,       // 9
		Int_2,       // 99
		Int_End,     // 9, | 9]
		Comma,       // ],
	}
	state_char := #partial [State]rune{
		.Brace_Open  = '{',
		.Quote_Open  = '"',
		.Quote_Close = '"',
		.Colon       = ':',
		.Array       = '[',
	}

	// parser state
	state: State
	buf := make([dynamic]byte, context.temp_allocator)
	char: rune
	char_num: bool
	buf_off: int
	size_max: [2]int
	line_height: int
	Char :: struct {char: rune, buf: []byte, pos, end: [2]int}
	chars := make([dynamic]Char, context.temp_allocator)
	has_space: bool

	parse: for c in string(bytes) {
		switch state {
		case .Brace_Open,
		     .Quote_Open,
		     .Quote_Close,
		     .Colon,
		     .Array:
			if unicode.is_white_space(c) do continue
			if c != state_char[state] {
				state = .Comma
				continue
			}
		case .Char:
			if char == 0 {
				if c == '"' {
					state = .Comma
					char = 0
				} else {
					char = c
					char_num = false
				}
			} else if char == '\\' && !char_num {
				char = c
				break
			} else if c >= '0' && c <= '9' {
				if !char_num do char -= '0'
				char = char * 10 + c - '0'
				char_num = true
			} else if c == '"' {
				state = .Colon
			} else {
				state = .Comma
				char = 0
			}
			continue
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
			state = .Int_End
			fallthrough
		case .Int_End:
			if unicode.is_white_space(c) do continue
			switch c {
			case ',':
				state = .Int_1
				continue
			case ']':
				if charset == nil || char in charset {
					pos := [2]int{8, 8}
					end := [2]int{0, 0}
					for row, ri in buf[buf_off:] {
						for bi in 0..<8 {
							if row & (1 << u8(bi)) != 0 {
								pos.x = min(pos.x, bi)
								end.x = max(end.x, bi+1)
							}
						}
						if row > 0 {
							pos.y = min(pos.y, ri)
							end.y = max(end.y, ri+1)
						}
					}
					end = linalg.max(pos, end)
					size_max = linalg.max(end-pos, size_max)
					line_height = max(len(buf)-buf_off, line_height)
					append(&chars, Char{char, buf[buf_off:], pos, end})
					buf_off = len(buf)
					has_space ||= char == ' '
				} else {
					resize(&buf, buf_off)
				}
				char = 0
			case:
				state = .Comma
				continue
			}
		case .Comma:
			if unicode.is_white_space(c) do continue
			switch c {
			case ',': // next state - next char
			case '}': break parse
			case:
				state = .Comma
				continue
			}
		}

		state = max(State((int(state) + 1) % len(State)), State.Quote_Open)
	}

	if !has_space {
		append(&chars, Char{' ', {}, 0, 0})
	}

	cols := min(len(chars), atlas_cols)
	rows := len(chars) / cols
	if rows * cols < len(chars) {
		rows += 1
	}

	atlas.size   = [2]int{cols, rows} * (size_max + atlas_gap) + atlas_gap
	atlas.pixels = make([]RGBA, atlas.size.x * atlas.size.y, allocator)

	glyphs := make([]Glyph, len(chars), allocator)

	for c, ci in chars {
		x := (ci % cols) * (size_max.x + atlas_gap) + atlas_gap
		y := (ci / cols) * (size_max.y + atlas_gap) + atlas_gap
		for row, yi in c.buf[c.pos.y:c.end.y] {
			for xi in c.pos.x ..< c.end.x {
				px := x + xi - c.pos.x
				py := y + yi
				if (row & (1 << u8(xi))) != 0 {
					atlas.pixels[py * atlas.size.x + px] = 255
				}
			}
		}
		size := c.end-c.pos
		glyphs[ci] = {
			char    = c.char,
			pos     = {i16(x), i16(y)},
			size    = ([2]i16)(size),
			off     = ([2]i16)(c.pos),
			advance = i16(size.x if size.x > 0 else space_width),
		}
		if c.char == ' ' do has_space = true
	}

	font.line_height = line_height
	font.base        = size_max.y
	font.scale       = 1

	font_set_glyphs(&font, glyphs, allocator)

	return
}
