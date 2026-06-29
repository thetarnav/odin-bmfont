// Static karl2d font path for BMFonts

package example

import "core:log"
import k2 "./karl2d"
import bmfont ".."

// Load a BMFont (XML + PNG) as a k2 Static font. The atlas is the BMFont's PNG, baked
// at the BMFont's native line height. After this, `k2.draw_text` can be called with any
// `font_size` — k2 scales the result by `font_size / prebaked_size` at draw time.
load_bmfont :: proc(
	state:     ^k2.State,
	$XML_PATH: string,
	$PNG_PATH: string,
) -> k2.Font {

	bm, ferr := bmfont.load_font_from_bytes(#load(XML_PATH), context.temp_allocator)
	if ferr != nil {
		log.errorf("Failed to load font XML %s: %v", XML_PATH, ferr)
		return k2.FONT_NONE
	}

	atlas_tex := k2.load_texture_from_bytes(#load(PNG_PATH))

	glyphs := make([]k2.Font_Baked_Glyph, len(bm.glyphs), state.allocator)
	for g, i in bm.glyphs {
		glyphs[i] = k2.Font_Baked_Glyph{
			value   = g.char,
			index   = i,
			rect    = {**k2.Vec2(g.pos), **k2.Vec2(g.size)},
			offset  = k2.Vec2(g.off),
			advance = f32(g.advance) + f32(bm.spacing.x),
		}
	}

	ranges := make([]k2.Font_Baked_Glyph_Range, len(bm.ranges), state.allocator)
	{
		offset: int
		for &range, i in ranges {
			r := bm.ranges[i]
			range = {
				start     = bm.glyphs[offset].char,
				end       = bm.glyphs[offset + r - 1].char,
				start_idx = offset,
			}
			offset += r
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
