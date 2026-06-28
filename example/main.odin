package example

import k2 "./karl2d"
import bmfont ".."

Vec2  :: bmfont.Vec2
Rect  :: bmfont.Rect
Color :: [4]u8

UI_W, UI_H  :: 320, 200
PIXEL_SCALE :: 4

COLOR_BIG   :: Color{255, 240, 200, 255}
COLOR_SMALL :: Color{200, 230, 255, 255}

Draw_Data :: struct {
	color: Color,
	tex:   ^k2.Texture,
}

// Karl2D draw callback. The user_data carries a ^k2.Texture; the bmfont `texture` argument is
// unused here so we leave it nil when constructing the renderer.
draw_cb: bmfont.Draw_Callback : proc (src: Rect, dst: Rect) {
	data := (^Draw_Data)(context.user_ptr)^
	k2.draw_texture_fit(
		data.tex^,
		{**src.pos, **src.size},
		{**dst.pos, **dst.size},
		tint = data.color,
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

	for {
		k2.update() or_break
		defer k2.reset_frame_allocator()
		defer free_all(context.temp_allocator)

		k2.clear({30, 30, 40, 255})

		context.user_ptr = &(Draw_Data{
			tex   = &tex_big,
			color = COLOR_BIG,
		})
		bmfont.draw_text("Bitmap Fonts!", font_big, draw_cb, scale=PIXEL_SCALE, origin={10, 10})

		context.user_ptr = &(Draw_Data{
			tex   = &tex_small,
			color = COLOR_SMALL,
		})
		bmfont.draw_text("The quick brown fox jumps over 12345", font_small, draw_cb, scale=PIXEL_SCALE, origin={10, 80})

		bmfont.draw_text("ABCDEF abcdef 0123456789", font_small, draw_cb, scale=PIXEL_SCALE, origin={10, 120})

		bmfont.draw_text("Multi-line\nis supported!", font_small, draw_cb, scale=PIXEL_SCALE, origin={10, 160})

		k2.present()
	}

	bmfont.destroy_font(font_big)
	bmfont.destroy_font(font_small)
	k2.destroy_texture(tex_big)
	k2.destroy_texture(tex_small)
	k2.shutdown()
}
