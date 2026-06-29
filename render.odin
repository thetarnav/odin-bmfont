package bmfont

import "core:math/linalg"

Vec2  :: [2]f32
Rect  :: struct {using pos: Vec2, size: Vec2}

Draw_Callback :: proc (
	src: Rect, // Source rectangle in atlas pixel space.
	dst: Rect, // Destination rectangle in screen/world pixel space.
)

// Draw a string of text starting at the current cursor. Advances the cursor past
// the drawn text. Supports '\n' for newlines (resets cursor.x to origin.x, advances y) and
// '\t' for tabs. Unknown codepoints advance the cursor by the width of a space glyph.
//
// `scale`  - controls how large each atlas pixel appears on screen.
//            Use 4 to render a 6px font at chunky 4x pixel-art size, or 1 for a 1:1 crisp look.
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
	text:   string,
	font:   Font,
	cb:     Draw_Callback,
	scale:  f32    = 1,
	origin: Vec2   = {0, 0},
	cursor: ^Vec2  = nil,
) -> (bounds: Rect) {

	c: Vec2 = cursor^ if cursor != nil else 0

	if cb == nil || len(font.glyphs) == 0 {
		return {origin + c, 0}
	}

	space_w  := (space_advance(font) + f32(font.spacing.x)) * scale
	line_h   := (f32(font.line_height) + f32(font.spacing.y)) * scale
	stretch  := f32(font.stretch_h) / 100.0 if font.stretch_h != 0 else 1
	extra_x  := f32(font.spacing.x) * scale

	lo := origin + {0, c.y}
	hi := lo

	for ch in text {
		if ch == '\n' {
			c.x = 0
			c.y += line_h
			lo.y = min(lo.y, origin.y + c.y)
			hi.y = max(hi.y, origin.y + c.y)
			continue
		}
		if ch == '\t' {
			c.x += space_w * 4
			hi.x = max(hi.x, origin.x + c.x)
			continue
		}
		glyph, ok := find_glyph(font, ch)
		if !ok {
			c.x += space_w
			hi.x = max(hi.x, origin.x + c.x)
			continue
		}

		s := Rect{Vec2(glyph.pos), Vec2(glyph.size)}
		d := Rect{
			pos  = origin + c + Vec2(glyph.off) * scale,
			size = {s.size.x * scale * stretch, s.size.y * scale},
		}
		cb(src=s, dst=d)

		c.x += f32(glyph.advance) * scale + extra_x
		hi = linalg.max(hi, origin + c + {0, line_h})
	}

	if cursor != nil {
		cursor^ = c
	}

	return {lo, linalg.max(hi - lo, 0)}
}

// Measure how much space a string would take up when drawn, without actually drawing it.
// Returns [width, height] in screen pixels. Supports '\n' and '\t'. Mirrors the
// `info.spacing` and `info.stretch_h` adjustments used by `draw_text`.
//
// Pass the same `scale` you would pass to `draw_text` to get the on-screen size.
measure_text :: proc (font: Font, text: string, scale: f32 = 1) -> Vec2 {

	if len(font.glyphs) == 0 {
		return 0
	}

	space_w  := (space_advance(font) + f32(font.spacing.x)) * scale
	line_h   := (f32(font.line_height) + f32(font.spacing.y)) * scale
	extra_x  := f32(font.spacing.x) * scale

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
		pen_x += f32(glyph.advance) * scale + extra_x
	}
	max_x = max(max_x, pen_x)

	return {max_x, max_y}
}

// Best-effort width of a space in this font, in atlas pixels. Tries the space glyph first,
// then falls back to the first glyph's advance, then to 6.
space_advance :: proc (font: Font) -> f32 {
	if g, ok := find_glyph(font, ' '); ok {
		return f32(g.advance)
	}
	for g in font.glyphs {
		return f32(g.advance)
	}
	return 6
}
