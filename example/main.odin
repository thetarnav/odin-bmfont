package example

import k2 "./karl2d"

UI_W, UI_H  :: 320, 200
PIXEL_SCALE :: 4

font_thick:    k2.Font
font_minogram: k2.Font
font_square:   k2.Font
font_round:    k2.Font

main :: proc () {

	k2_state := k2.init(UI_W, UI_H, "Bitmap Font (static) Example",
		options = {window_mode = .Windowed_Resizable})

	// The camera scales the entire UI from the logical 320x200 viewport up to actual
	// window pixels. Origins and font_size stay in logical units inside the draw loop.
	k2.set_camera(k2.Camera{zoom = f32(PIXEL_SCALE)})

	// Pre-bake every BMFont in fonts/ as a k2 Static font (defined in static_fonts.odin).
	font_thick    = load_bmfont_as_static(k2_state, "../fonts/thick_8x8.xml",     "../fonts/thick_8x8.png")
	font_minogram = load_bmfont_as_static(k2_state, "../fonts/minogram_6x10.xml", "../fonts/minogram_6x10.png")
	font_square   = load_bmfont_as_static(k2_state, "../fonts/square_6x6.xml",    "../fonts/square_6x6.png")
	font_round    = load_bmfont_as_static(k2_state, "../fonts/round_6x6.xml",     "../fonts/round_6x6.png")

	for k2.update() {
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})

		// The cursor auto-advances on every draw; each block just sets the y and
		// calls draw_line / draw_paragraph without computing offsets by hand.
		cursor := Text_Cursor{ pos = {10, 8} }

		draw_line(font_thick, "BITMAP FONTS!", 12, {255, 220, 160, 255}, &cursor)
		cursor.pos.y += 2

		draw_line(font_minogram, "All four BMFonts, one example", 12, {200, 255, 220, 255}, &cursor)
		cursor.pos.y += 2

		draw_paragraph(
			font_square,
			"The quick brown fox jumps over the lazy dog. " +
				"0123456789 !@#$%^&*() This paragraph is laid out by draw_paragraph, " +
				"which uses k2.measure_text to wrap each line at the available width.",
			9, 200, {200, 230, 255, 255}, &cursor,
		)
		cursor.pos.y += 2

		draw_line(font_round, "= round_6x6 =", 9, {255, 200, 200, 255}, &cursor)

		k2.present()
	}

	k2.shutdown()
}
