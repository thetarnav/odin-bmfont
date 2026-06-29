package example

// Static k2 font path for BMFonts — bypasses fontstash entirely.
//
// k2's `Static` font type stores a pre-baked atlas and an array of `Font_Baked_Glyph`
// records. `draw_text_static` iterates the text, looks up each codepoint, and renders
// each glyph directly with `k2.draw_texture_fit`. There is no fontstash, no TTF shim,
// no dynamic atlas — the bitmap is uploaded once at load and k2 scales it by
// `font_size / static_font_size` at draw time.

import k2   "./karl2d"
import bmfont ".."
import "core:image"
import "core:log"
import "core:slice"

// Load a BMFont (XML + PNG) as a k2 Static font. The atlas is the BMFont's PNG, baked
// at the BMFont's native line height. After this, `k2.draw_text` can be called with any
// `font_size` — k2 scales the result by `font_size / prebaked_size` at draw time.
load_bmfont_as_static :: proc(
	state:     ^k2.State,
	$XML_PATH: string,
	$PNG_PATH: string,
	allocator := context.allocator,
) -> k2.Font {

	bm, ferr := bmfont.load_font_from_bytes(#load(XML_PATH), context.temp_allocator)
	if ferr != nil {
		log.errorf("Failed to load font XML %s: %v", XML_PATH, ferr)
		return k2.FONT_NONE
	}

	img, ierr := image.load_from_bytes(#load(PNG_PATH), options = {.alpha_add_if_missing})
	if ierr != nil {
		log.errorf("Failed to load PNG %s: %v", PNG_PATH, ierr)
		return k2.FONT_NONE
	}

	// k2.Image uses `[]Color` (i.e. `[][4]u8`) for its pixel buffer; the core:image
	// buffer is the same byte layout (RGBA u8), so a reinterpret is enough.
	pixels := slice.reinterpret([]k2.Color, img.pixels.buf[:])
	atlas_tex := k2.load_texture_from_image(k2.Image{
		pixels = pixels,
		width  = img.width,
		height = img.height,
	})

	// One Font_Baked_Glyph per BMFont glyph, in codepoint order. `index` is unused by
	// draw_text_static's lookup path (it only reads `value` and `rect/offset/advance`),
	// but k2 still requires the field to be set. `info.spacing.x` is folded into
	// the stored advance so k2's `char_offset.x += g.advance * scl` picks it up automatically.
	spacing_x := f32(bm.spacing.x)
	glyphs := make([]k2.Font_Baked_Glyph, len(bm.glyphs), allocator)
	for g, i in bm.glyphs {
		glyphs[i] = k2.Font_Baked_Glyph{
			value   = g.char,
			index   = i,
			rect    = {**k2.Vec2(g.pos), **k2.Vec2(g.size)},
			offset  = k2.Vec2(g.off),
			advance = f32(g.advance) + spacing_x,
		}
	}

	// One range per glyph. draw_text_static does a linear scan over `static_glyph_ranges`,
	// so this is O(N) per codepoint; fine for the small ASCII sets these BMFonts ship.
	ranges := make([]k2.Font_Baked_Glyph_Range, len(bm.glyphs), allocator)
	for g, i in bm.glyphs {
		ranges[i] = k2.Font_Baked_Glyph_Range{
			start_idx = i,
			start     = g.char,
			end       = g.char + 1,
		}
	}

	append(&state.fonts, k2.Font_Data{
		atlas               = atlas_tex,
		type                = .Static,
		static_glyphs       = glyphs,
		static_glyph_ranges = ranges,
		static_font_size    = f32(bm.line_height),
		static_line_spacing = f32(bm.line_height) + f32(bm.spacing.y),
	})

	return k2.Font(len(state.fonts) - 1)
}
