package bmfont

// A 2D rectangle: [x, y, w, h]. Follows the convention of most 2D rendering backends.
Rect :: [4]f32

// An RGBA color. Each channel is in the range 0..255.
Color :: [4]u8

// A single draw operation the renderer wants to issue. The user's draw callback receives one
// of these for every glyph.
Draw_Call :: struct {
	// Source rectangle in atlas pixel space.
	src: Rect,

	// Destination rectangle in screen/world pixel space.
	dst: Rect,

	// Tint to apply multiplicatively (so {255,255,255,255} means no tinting).
	color: Color,
}

// Callback the user provides to forward a draw call to their backend.
//
// `texture` is the opaque handle the user passed to `renderer_init` (e.g. a karl2d texture,
// or anything else cast to `rawptr`). It is forwarded verbatim on every call.
//
// `user_data` is whatever the user passed to `renderer_init` for additional context. Use it
// to carry backend-specific state (the actual texture struct, transforms, etc.).
Draw_Callback :: proc(texture: rawptr, call: Draw_Call, user_data: rawptr)

// A generic, backend-agnostic renderer for a parsed BMFont.
//
// Holds a font, an opaque texture handle, an RGBA tint, a scale, and a draw callback.
// `draw_text` walks the string, looks up each glyph, and emits a draw call via the callback.
// The renderer never references any specific backend — it only produces (src, dst, color)
// tuples, leaving the actual GPU call up to the user.
//
// All positions and sizes are in screen/world pixels. The font atlas is in source pixels;
// the renderer multiplies atlas coordinates by `scale` (default 1) to produce screen pixels.
Renderer :: struct {
	font:      ^Font,
	texture:   rawptr,
	color:     Color,
	scale:     f32,
	origin:    [2]f32, // top-left anchor in screen pixels
	cursor:    [2]f32, // current pen position, relative to origin, in screen pixels
	cb:        Draw_Callback,
	user_data: rawptr,
}

// Initialize a renderer. Returns the same pointer for chaining.
//
// `texture` is an opaque handle to the font's atlas texture. The renderer doesn't manage its
// lifetime; the caller is responsible for loading and destroying it.
//
// `cb` is invoked once per glyph to draw. The user forwards it to their backend of choice.
//
// `scale` controls how large each atlas pixel appears on screen. Use 4 to render a 6px font
// at chunky 4x pixel-art size, or 1 for a 1:1 crisp look.
renderer_init :: proc(
	r: ^Renderer,
	font: ^Font,
	texture: rawptr,
	cb: Draw_Callback,
	user_data: rawptr = nil,
	color: Color = {255, 255, 255, 255},
	scale: f32 = 1,
) -> ^Renderer {
	r.font      = font
	r.texture   = texture
	r.color     = color
	r.scale     = scale
	r.origin    = {0, 0}
	r.cursor    = {0, 0}
	r.cb        = cb
	r.user_data = user_data
	return r
}

// Move the pen to an absolute screen position. The next `draw_text` call starts drawing from
// here, with the cursor's x-component reset to zero relative to the new origin.
renderer_set_pos :: proc(r: ^Renderer, x, y: f32) {
	r.origin = {x, y}
	r.cursor = {0, 0}
}

// Set the renderer's color (tint). Each glyph is multiplied by this color when drawn.
renderer_set_color :: proc(r: ^Renderer, color: Color) {
	r.color = color
}

// Set the renderer's scale (multiplier from atlas pixels to screen pixels).
renderer_set_scale :: proc(r: ^Renderer, scale: f32) {
	r.scale = scale
}

// Draw a string of text starting at the renderer's current cursor. Advances the cursor past
// the drawn text. Supports '\n' for newlines (resets cursor.x to origin.x, advances y) and
// '\t' for tabs. Unknown codepoints advance the cursor by the width of a space glyph.
//
// Returns the bounding rectangle of the drawn text in screen pixels, including the origin.
// Useful for hit-testing or positioning subsequent text.
draw_text :: proc(r: ^Renderer, text: string) -> Rect {
	if r.cb == nil || r.font == nil || len(r.font.glyphs) == 0 {
		return {r.origin.x + r.cursor.x, r.origin.y + r.cursor.y, 0, 0}
	}

	pen_x := r.cursor.x
	pen_y := r.cursor.y

	space_w := space_advance(r.font) * r.scale
	line_h  := f32(r.font.line_height) * r.scale

	min_x := r.origin.x
	max_x := r.origin.x
	min_y := r.origin.y + pen_y
	max_y := min_y

	for ch in text {
		if ch == '\n' {
			pen_x = 0
			pen_y += line_h
			min_y = min(min_y, r.origin.y + pen_y)
			max_y = max(max_y, r.origin.y + pen_y)
			continue
		}
		if ch == '\t' {
			pen_x += space_w * 4
			max_x = max(max_x, r.origin.x + pen_x)
			continue
		}
		glyph, ok := find_glyph(r.font, ch)
		if !ok {
			pen_x += space_w
			max_x = max(max_x, r.origin.x + pen_x)
			continue
		}

		sx := f32(glyph.pos.x)
		sy := f32(glyph.pos.y)
		sw := f32(glyph.size.x)
		sh := f32(glyph.size.y)

		dx := r.origin.x + pen_x + f32(glyph.off.x) * r.scale
		dy := r.origin.y + pen_y + f32(glyph.off.y) * r.scale
		dw := sw * r.scale
		dh := sh * r.scale

		r.cb(r.texture, Draw_Call {
			src   = {sx, sy, sw, sh},
			dst   = {dx, dy, dw, dh},
			color = r.color,
		}, r.user_data)

		pen_x += f32(glyph.advance) * r.scale
		max_x = max(max_x, r.origin.x + pen_x)
		max_y = max(max_y, r.origin.y + pen_y + line_h)
	}

	r.cursor = {pen_x, pen_y}

	return {min_x, min_y, max(max_x - min_x, 0), max(max_y - min_y, 0)}
}

// Measure how much space a string would take up when drawn, without actually drawing it.
// Returns [width, height] in screen pixels. Supports '\n' and '\t'.
//
// Pass the same `scale` you would pass to `renderer_init` to get the on-screen size.
measure_text :: proc(font: ^Font, text: string, scale: f32 = 1) -> [2]f32 {
	if font == nil || len(font.glyphs) == 0 {
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
find_glyph :: proc(font: ^Font, ch: rune) -> (Font_Glyph, bool) {
	if font == nil do return {}, false

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
space_advance :: proc(font: ^Font) -> f32 {
	if g, ok := find_glyph(font, ' '); ok {
		return f32(g.advance)
	}
	for g in font.glyphs {
		return f32(g.advance)
	}
	return 6
}
