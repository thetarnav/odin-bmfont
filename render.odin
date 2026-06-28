package bmfont

Vec2  :: [2]f32
Rect  :: struct {using pos: Vec2, size: Vec2}
Color :: [4]u8

Draw_Callback :: proc (
	src:   Rect,  // Source rectangle in atlas pixel space.
	dst:   Rect,  // Destination rectangle in screen/world pixel space.
	color: Color, // Tint to apply multiplicatively (so {255,255,255,255} means no tinting).
)

// Draw a string of text starting at the renderer's current cursor. Advances the cursor past
// the drawn text. Supports '\n' for newlines (resets cursor.x to origin.x, advances y) and
// '\t' for tabs. Unknown codepoints advance the cursor by the width of a space glyph.
//
// `scale`  - controls how large each atlas pixel appears on screen.
//            Use 4 to render a 6px font at chunky 4x pixel-art size, or 1 for a 1:1 crisp look.
// `origin` - top-left anchor in screen pixels
// `cursor` - current pen position, relative to origin, in screen pixels
//
// Returns the bounding rectangle of the drawn text in screen pixels, including the origin.
// Useful for hit-testing or positioning subsequent text.
draw_text :: proc(
	text:   string,
	font:   Font,
	cb:     Draw_Callback,
	color:  Color  = {255, 255, 255, 255},
	scale:  f32    = 1,
	origin: Vec2   = {0, 0},
	cursor: ^Vec2  = nil,
) -> Rect {

	c: Vec2 = cursor^ if cursor != nil else 0

	if cb == nil || len(font.glyphs) == 0 {
		return {origin + c, 0}
	}

	pen_x := c.x
	pen_y := c.y

	space_w := space_advance(font) * scale
	line_h  := f32(font.line_height) * scale

	min_x := origin.x
	max_x := origin.x
	min_y := origin.y + pen_y
	max_y := min_y

	for ch in text {
		if ch == '\n' {
			pen_x = 0
			pen_y += line_h
			min_y = min(min_y, origin.y + pen_y)
			max_y = max(max_y, origin.y + pen_y)
			continue
		}
		if ch == '\t' {
			pen_x += space_w * 4
			max_x = max(max_x, origin.x + pen_x)
			continue
		}
		glyph, ok := find_glyph(font, ch)
		if !ok {
			pen_x += space_w
			max_x = max(max_x, origin.x + pen_x)
			continue
		}

		sx := f32(glyph.pos.x)
		sy := f32(glyph.pos.y)
		sw := f32(glyph.size.x)
		sh := f32(glyph.size.y)

		dx := origin.x + pen_x + f32(glyph.off.x) * scale
		dy := origin.y + pen_y + f32(glyph.off.y) * scale
		dw := sw * scale
		dh := sh * scale

		cb(src   = {{sx, sy}, {sw, sh}},
		   dst   = {{dx, dy}, {dw, dh}},
		   color = color)

		pen_x += f32(glyph.advance) * scale
		max_x = max(max_x, origin.x + pen_x)
		max_y = max(max_y, origin.y + pen_y + line_h)
	}

	if cursor != nil {
		cursor^ = {pen_x, pen_y}
	}

	return {{min_x, min_y}, {max(max_x - min_x, 0), max(max_y - min_y, 0)}}
}

// Measure how much space a string would take up when drawn, without actually drawing it.
// Returns [width, height] in screen pixels. Supports '\n' and '\t'.
//
// Pass the same `scale` you would pass to `renderer_init` to get the on-screen size.
measure_text :: proc (font: Font, text: string, scale: f32 = 1) -> [2]f32 {
	if len(font.glyphs) == 0 {
		return {0, 0}
	}

	space_w := space_advance(font) * scale
	line_h  := f32(font.line_height) * scale

	pen_x: f32 = 0
	pen_y: f32 = 0
	max_x: f32 = 0
	max_y: f32 = line_h

	for ch in text {
		if ch == '\n' {
			max_x = max(max_x, pen_x)
			pen_x = 0
			pen_y += line_h
			max_y = max(max_y, pen_y + line_h)
			continue
		}
		if ch == '\t' {
			pen_x += space_w * 4
			continue
		}
		glyph, ok := find_glyph(font, ch)
		if !ok {
			pen_x += space_w
			continue
		}
		pen_x += f32(glyph.advance) * scale
	}
	max_x = max(max_x, pen_x)

	return {max_x, max_y}
}

// Find a glyph by codepoint using binary search. Glyphs are sorted by char at load time.
// Returns the glyph and true on success, or a zero glyph and false if not found.
find_glyph :: proc(font: Font, ch: rune) -> (Font_Glyph, bool) {

	lo, hi := 0, len(font.glyphs)
	for lo < hi {
		mid := (lo + hi) / 2
		if font.glyphs[mid].char < ch {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < len(font.glyphs) && font.glyphs[lo].char == ch {
		return font.glyphs[lo], true
	}
	return {}, false
}

// Best-effort width of a space in this font, in atlas pixels. Tries the space glyph first,
// then falls back to the first glyph's advance, then to 6.
space_advance :: proc(font: Font) -> f32 {
	if g, ok := find_glyph(font, ' '); ok {
		return f32(g.advance)
	}
	for g in font.glyphs {
		return f32(g.advance)
	}
	return 6
}
