# Odin BMFont

Bitmap font parser and render helpers for Odin.

![Odin BMFont example preview](https://github.com/user-attachments/assets/3b7ae70a-58cf-407b-86ff-ce2e04270d85)

Currently supports parsing following BMFont formats:

- **XML** — Standard BMFont XML *(`.xml`, `.fnt`)*, produced by virtually every exporter.
    Requires a separate atlas texture.
    Check `./fonts/WhitePeaberry.xml` for example.
- **Text** — AngelCode's text format *(`.txt`, `.fnt`)* — one tag per line followed by `key=value` pairs.
    Check `./fonts/WhitePeaberry.txt` for example.
    Requires a separate atlas texture.
- **JSON byte stream** — Each character's pixels are encoded directly as bit-pattern
    entries in a JSON map. The parser packs them into a virtual atlas for you.
    Check `./fonts/monogram-bitfontmaker.json` for example.

## Usage

### Parsing

```odin
import "bmfont"

// Load and parse your XML font to bmfont.Font
font, err := bmfont.load_bmfont_xml(#load("fonts/WhitePeaberry.xml"))
defer bmfont.destroy_font(font) // Remember to free it after use

// Text format is also supported
font, err := bmfont.load_bmfont_text(#load("fonts/WhitePeaberry.txt"),
                                     allocator=context.temp_allocator)

// JSON bytestream — returns the `Font` and `Atlas :: struct {pixels: [][4]u8, size: [2]int}`
font, atlas, err := bmfont.load_json_bytestream(
    #load("fonts/monogram-bitfontmaker.json"),
    include     = "", // string of codepoints to keep in atlas/font; empty keeps everything
    space_width = 4,  // space glyph is made from empty bytes, so you need to set it's width explicitly
    atlas_cols  = 10, // how many glyphs should be in the atlas horizontally
    atlas_gap   = 1,  // gap in pixels between glyphs in atlas
    allocator   = context.temp_allocator,
)
defer delete(atlas.pixels) // atlas pixels are allocated with `allocator` param
```

`find_glyph(font, codepoint)` resolves a rune to a `Glyph` in O(runs of
consecutive codepoints) via the per-font `ranges` table.

### Drawing

`draw_text` is backend-agnostic.\
Each glyph turn calls the callback with the source rect (in atlas pixels)\
and the destination rect (in screen pixels)\
so the caller can blit however it likes:

```odin
import "bmfont"

bmfont.draw_text("Hello", font,
    my_draw_callback,  // proc (src, dst: Rect)
    scale  = 4,        // atlas-pixel-to-screen-pixel multiplier
    origin = {10, 10}, // top-left of the text in screen pixels
    cursor = &cursor,  // optional pen position; updated as text advances
)
```

Newlines (`\n`) reset the pen to `origin.x` and advance y by the line height.\
Tabs (`\t`) advance the pen by four spaces.\
Unknown codepoints fall through to the next glyph with a space-width advance.

`font.info.spacing.x` (horizontal) is added to each glyph's advance, and
`font.info.spacing.y` (vertical) is added to the line height, so the BMFont
`<info spacing="…">` attribute flows through to the layout automatically.

### Measuring

`measure_text(text, font, scale)` returns the `[width, height]` in screen
pixels the text would occupy. Use it to size a container, compute a wrap width,
or pre-compute a cursor offset without drawing:

```odin
size := bmfont.measure_text("Hello, world!", font, scale=4)
if size.x > max_width {
    // wrap, truncate, or fall back to a smaller font_size
}
```

`space_advance(font)` returns the pixel advance of a single space\
(used as the fallback when a codepoint isn't in the font).

## Example

In [`example/`](./example/) you'll see how to draw some text using bitmap fonts.

```sh
make # or `odin run example`
```

It uses [karl2d](https://github.com/karl-zylinski/karl2d) for windowing and rendering.\
It requires to have it in the `shared:` odin collection. (`odin/shared/karl2d`)

See [`example/static_fonts.odin`](./example/static_fonts.odin) for how can bmfonts be loaded directly to `karl2d` state,\
so you can use `k2.draw_text()` and `k2.measure_text()` with bmfonts.

## Resources

- [AngelCode's Bitmap Font Generator Documentation](https://www.angelcode.com/products/bmfont/doc/file_format.html)
- [SnowB BMF's export formats docs](https://snowb.org/en/docs/project-management/export-formats)

## License

- Odin library — [MIT License](./LICENSE.txt)

- [`example/`](./example/) — Public Domain

- [Peaberry font](https://emhuo.itch.io/peaberry-pixel-font) — by [Emily (emhuo)](https://emhuo.itch.io) — [Open Font License Version 1.1](./fonts/LICENSE_Peaberry.txt)
  - [`fonts/WhitePeaberry.png`](./fonts/WhitePeaberry.png)
  - [`fonts/WhitePeaberry.txt`](./fonts/WhitePeaberry.txt)
  - [`fonts/WhitePeaberry.xml`](./fonts/WhitePeaberry.xml)

- [Monogram font](https://datagoblin.itch.io/monogram) — by [Datagoblin](https://datagoblin.itch.io) — [CC0](https://creativecommons.org/publicdomain/zero/1.0)
  - [`fonts/monogram-bitfontmaker.json`](./fonts/monogram-bitfontmaker.json)
  - [`fonts/monogram-bitmap.json`](./fonts/monogram-bitmap.json)

- [Pixel Bitmap Fonts](https://frostyfreeze.itch.io/pixel-bitmap-fonts-png-xml) — by [frostyfreeze](https://frostyfreeze.itch.io) — CC0 / Public Domain
  - [`fonts/minogram_6x10.png`](./fonts/minogram_6x10.png)
  - [`fonts/minogram_6x10.xml`](./fonts/minogram_6x10.xml)
  - [`fonts/round_6x6.png`](./fonts/round_6x6.png)
  - [`fonts/round_6x6.xml`](./fonts/round_6x6.xml)
  - [`fonts/square_6x6.png`](./fonts/square_6x6.png)
  - [`fonts/square_6x6.xml`](./fonts/square_6x6.xml)
  - [`fonts/thick_8x8.png`](./fonts/thick_8x8.png)
  - [`fonts/thick_8x8.xml`](./fonts/thick_8x8.xml)

