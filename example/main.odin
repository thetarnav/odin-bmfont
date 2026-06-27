package example

import k2 "./karl2d"

UI_W, UI_H :: 320, 200
PIXEL_SCALE :: 4

init :: proc () {
	k2.init(UI_W * PIXEL_SCALE, UI_H * PIXEL_SCALE, "Pixui Example",
		options = {window_mode = .Windowed_Resizable})
}

step :: proc () -> bool {

	k2.update() or_return
	defer k2.reset_frame_allocator()
	defer free_all(context.temp_allocator)

	k2.clear({30, 30, 40, 255})

	k2.present()
	return true
}

shutdown :: proc () {
	k2.shutdown()
}

main :: proc () {
	init()
	for step() {}
	shutdown()
}
