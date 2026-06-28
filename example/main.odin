package example

import k2 "./karl2d"

UI_W, UI_H  :: 320, 200
PIXEL_SCALE :: 4

font_big:   k2.Font
font_small: k2.Font

main :: proc () {

	k2_state := k2.init(UI_W, UI_H, "Bitmap Font (static) Example",
		options = {window_mode = .Windowed_Resizable})

	// The camera scales the entire UI from the logical 320x200 viewport up to actual
	// window pixels. Origins and font_size stay in logical units inside the draw loop.
	k2.set_camera(k2.Camera{zoom = f32(PIXEL_SCALE)})

	// Pre-bake each BMFont as a k2 Static font (defined in static_fonts.odin). They are
	// stored at the BMFont's native line height; k2.draw_text scales by font_size / native
	// at draw time, so any font_size works.
	font_big   = load_bmfont_as_static(k2_state, "../fonts/minogram_6x10.xml", "../fonts/minogram_6x10.png")
	font_small = load_bmfont_as_static(k2_state, "../fonts/square_6x6.xml",   "../fonts/square_6x6.png")

	for k2.update() {
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})

		k2.draw_text("Bitmap Fonts!", {10, 10}, 12, {255, 240, 200, 255}, font_big)

		k2.draw_text("The quick brown fox jumps over 12345", {10, 80}, 9, {200, 230, 255, 255}, font_small)
		k2.draw_text("ABCDEF abcdef 0123456789",                {10, 120}, 9, {200, 230, 255, 255}, font_small)
		k2.draw_text("Multi-line\nis supported!",                {10, 160}, 9, {200, 230, 255, 255}, font_small)

		k2.present()
	}

	k2.shutdown()
}
