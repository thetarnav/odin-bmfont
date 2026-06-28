package example

import k2 "./karl2d"
import bmfont ".."

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

// Karl2D draw callback. The user_data carries a ^k2.Texture; the bmfont `texture` argument is
// unused here so we leave it nil when constructing the renderer.
k2_draw_cb :: proc(texture: rawptr, call: bmfont.Draw_Call, user_data: rawptr) {
	k2.draw_texture_fit(
		(^k2.Texture)(user_data)^,
		{**call.src.pos, **call.src.size},
		{**call.dst.pos, **call.dst.size},
		tint = {call.color.r, call.color.g, call.color.b, call.color.a},
	)
}

main :: proc () {

	k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Bitmap Font Example",
		options = {window_mode = .Windowed_Resizable})

	// Load two fonts from XML and their atlas textures, then create a renderer for each.
	font_big, _   := bmfont.load_font_from_bytes(#load("../fonts/minogram_6x10.xml"))
	font_small, _ := bmfont.load_font_from_bytes(#load("../fonts/square_6x6.xml"))
	tex_big       := k2.load_texture_from_bytes(#load("../fonts/minogram_6x10.png"))
	tex_small     := k2.load_texture_from_bytes(#load("../fonts/square_6x6.png"))

	ren_big:   bmfont.Renderer
	ren_small: bmfont.Renderer

	bmfont.renderer_init(
		&ren_big, font_big, nil, k2_draw_cb, &tex_big,
		color = {255, 240, 200, 255},
		scale = f32(PIXEL_SCALE),
	)
	bmfont.renderer_init(
		&ren_small, font_small, nil, k2_draw_cb, &tex_small,
		color = {200, 230, 255, 255},
		scale = f32(PIXEL_SCALE),
	)

	for {
		k2.update() or_break
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})

		bmfont.renderer_set_pos(&ren_big, 10, 10)
		bmfont.draw_text(&ren_big, "Bitmap Fonts!")

		bmfont.renderer_set_pos(&ren_small, 10, 80)
		bmfont.draw_text(&ren_small, "The quick brown fox jumps over 12345")

		bmfont.renderer_set_pos(&ren_small, 10, 120)
		bmfont.draw_text(&ren_small, "ABCDEF abcdef 0123456789")

		bmfont.renderer_set_pos(&ren_small, 10, 160)
		bmfont.draw_text(&ren_small, "Multi-line\nis supported!")

		k2.present()
	}

	bmfont.destroy_font(font_big)
	bmfont.destroy_font(font_small)
	k2.destroy_texture(tex_big)
	k2.destroy_texture(tex_small)
	k2.shutdown()
}
