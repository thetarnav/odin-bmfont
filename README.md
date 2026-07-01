# Odin BMFont

Bitmap font parser and render helpers for Odin.

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

Render helpers include `draw_text` and `measure_text`.

## Usage

### Parsing

```odin
import bmfont ".."

// XML / Text — return a `bmfont.Font`. Both need a paired atlas texture uploaded
// separately; the JSON variant carries its own pixel data instead.
font, err := bmfont.load_bmfont(#load("fonts/WhitePeaberry.xml"), .XML, context.temp_allocator)
font, err = bmfont.load_bmfont(#load("fonts/WhitePeaberry.txt"), .Text, context.temp_allocator)

// JSON bytestream — returns the `Font` plus an `Atlas { pixels: []RGBA, size: [2]int }`
// holding the raw RGBA8 atlas bytes the caller uploads as a texture.
// `include` is a string of codepoints to keep; empty keeps everything.
font, atlas, err := bmfont.load_json_bytestream(
    #load("fonts/monogram-bitfontmaker.json"),
    include      = "",
    space_width  = 4,
    atlas_cols   = 10,
    atlas_gap    = 1,
    allocator    = context.temp_allocator,
)
```

`bmfont.find_glyph(font, codepoint)` resolves a rune to a `Glyph` in O(runs of
consecutive codepoints) via the per-font `ranges` table.

### Drawing

`render.draw_text` is backend-agnostic — it takes a `Draw_Callback` that the
caller supplies. Each glyph turn calls the callback with the source rect (in
atlas pixels) and the destination rect (in screen pixels) so the caller can
blit however it likes:

```odin
import bmfont ".."

draw_text(
    "Hello",
    font,
    my_draw_callback,    // proc(src, dst: Rect)
    scale   = 4,          // atlas-pixel-to-screen-pixel multiplier
    origin  = {10, 10},   // top-left of the text in screen pixels
    cursor  = &cursor,    // optional pen position; updated as text advances
)
```

Newlines (`\n`) reset the pen to `origin.x` and advance y by the line height.
Tabs (`\t`) advance the pen by four spaces. Unknown codepoints fall through to
the next glyph with a space-width advance.

`font.info.spacing[0]` (horizontal) is added to each glyph's advance, and
`font.info.spacing[1]` (vertical) is added to the line height, so the BMFont
`<info spacing="…">` attribute flows through to the layout automatically.

### Measuring

`render.measure_text(text, font, scale)` returns the `[width, height]` in screen
pixels the text would occupy. Use it to size a container, compute a wrap width,
or pre-compute a cursor offset without drawing:

```odin
size := render.measure_text("Hello, world!", font, scale = 4)
if size.x > max_width {
    // wrap, truncate, or fall back to a smaller font_size
}
```

`render.space_advance(font)` returns the pixel advance of a single space (used
as the fallback when a codepoint isn't in the font).

### karl2d setup

For an end-to-end example that ties parsing → atlas upload → k2 static font
registration, see `example/static_fonts.odin`. It has two procs:

- `load_bmfont(state, $XML_PATH, $PNG_PATH) -> k2.Font` — XML/Text + PNG pair.
- `load_bmfont_json(state, $JSON_PATH) -> k2.Font` — JSON bytestream.

Both call into the library, then upload the atlas (PNG or in-memory RGBA),
build the `k2.Font_Baked_Glyph` / `k2.Font_Baked_Glyph_Range` tables, and append
a `k2.Font_Data` to `state.fonts`. After that, `k2.draw_text(text, pos, size,
color, font)` works the same way as for any k2 font.

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

