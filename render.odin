package bmfont

import "core:math/linalg"

Vec2 :: [2]int
Rect :: struct {using pos: Vec2, size: Vec2}

Draw_Callback :: proc (
	src: Rect, // Source rectangle in atlas pixel space.
	dst: Rect, // Destination rectangle in screen/world pixel space.
)

// Draw a string of text starting at the current cursor. Advances the cursor past
// the drawn text. Supports '\n' for newlines (resets cursor.x to origin.x, advances y) and
// '\t' for tabs. Unknown codepoints advance the cursor by the width of a space glyph.
//
// `origin` - top-left anchor in screen pixels
// `cursor` - current pen position, relative to origin, in screen pixels
//
// `font.info.spacing[0]` (horizontal) is added to each glyph's advance, and
// `font.info.spacing[1]` (vertical) is added to the line height. `font.info.stretch_h`
// (default 100) scales the destination glyph width. Default zero values for the simple
// BMFonts in this repo make these no-ops.
//
// Returns the bounding rectangle of the drawn text in screen pixels, including the origin.
// Useful for hit-testing or positioning subsequent text.
draw_text :: proc(
	text:      string,
	font:      Font,
	cb:        Draw_Callback,
	origin:    Vec2       = {0, 0},
	cursor:    ^Vec2      = nil,
	tab_width: Maybe(int) = nil,
) -> (bounds: Rect) {

	c: Vec2 = cursor^ if cursor != nil else 0

	if cb == nil || len(font.glyphs) == 0 {
		return {origin + c, 0}
	}

	sw := space_width(font)
	tw := tab_width.? or_else sw * 4
	lh := line_height(font)
	ex := font.spacing.x
	stretch := font.stretch_h / 100 if font.stretch_h != 0 else 1

	lo := origin + {0, c.y}
	hi := lo

	for ch in text {
		if ch == '\n' {
			c.x = 0
			c.y += lh
			lo.y = min(lo.y, origin.y + c.y)
			hi.y = max(hi.y, origin.y + c.y)
			continue
		}
		if ch == '\t' {
			c.x += tw
			hi.x = max(hi.x, origin.x + c.x)
			continue
		}
		glyph, ok := find_glyph(font, ch)
		if !ok {
			c.x += sw
			hi.x = max(hi.x, origin.x + c.x)
			continue
		}

		s := Rect{Vec2(glyph.pos), Vec2(glyph.size)}
		d := Rect{pos  = origin + c + Vec2(glyph.off),
		          size = {s.size.x * stretch, s.size.y}}
		cb(src=s, dst=d)

		c.x += int(glyph.advance) + ex
		hi = linalg.max(hi, origin + c + {0, lh})
	}

	if cursor != nil {
		cursor^ = c
	}

	return {lo, linalg.max(hi - lo, 0)}
}

// Measure how much space a string would take up when drawn, without actually drawing it.
// Returns [width, height] in screen pixels. Supports '\n' and '\t'. Mirrors the
// `info.spacing` and `info.stretch_h` adjustments used by `draw_text`.
measure_text :: proc (font: Font, text: string, tab_width: Maybe(int) = nil) -> Vec2 {

	if len(font.glyphs) == 0 {
		return 0
	}

	sw := space_width(font)
	tw := tab_width.? or_else sw * 4
	lh := line_height(font)
	ex := font.spacing.x

	pen_x, pen_y, max_x, max_y: int
	max_y = lh

	for ch in text {
		if ch == '\n' {
			max_x = max(max_x, pen_x)
			pen_x = 0
			pen_y += lh
			max_y = max(max_y, pen_y + lh)
			continue
		}
		if ch == '\t' {
			pen_x += tw
			continue
		}
		glyph, ok := find_glyph(font, ch)
		if ok {
			pen_x += int(glyph.advance) + ex
		} else {
			pen_x += sw
		}
	}
	max_x = max(max_x, pen_x)

	return {max_x, max_y}
}

// Best-effort width of a space in this font, in atlas pixels. Tries the space glyph first,
// then falls back to the first glyph's advance, then to 6.
space_advance :: proc (font: Font) -> int {
	if g, ok := find_glyph(font, ' '); ok {
		return int(g.advance)
	}
	for g in font.glyphs {
		return int(g.advance)
	}
	return 6
}

space_width :: proc (font: Font) -> int {
	return space_advance(font) + font.spacing.x
}
line_height :: proc (font: Font) -> int {
	if font.line_height > 0 {
		return font.line_height + font.spacing.y
	}
	g, _ := find_glyph(font, 'M')
	return int(g.size.y) + font.spacing.y
}
