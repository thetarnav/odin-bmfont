# Odin BMFont

Bitmap font parser and render helpers for Odin.

Currently supports parsing following BMFont formats:

- **XML** — Standard BMFont XML *(`.xml`, `.fnt`)*, produced by virtually every exporter.
    Requires a separate atlas texture.
    Check `./fonts/WhitePeaberry.xml` for example.
- **Text** — AngelCode's text format *(`.txt`, `.fnt`)* — one tag per line followed by `key=value` pairs.
    Check `./fonts/WhitePeaberry.txt` for example.
    Requires a separate atlas texture.
- **JSON byte stream** — Encodes each character pixels directly in byte row bitmaps.
    Check `./fonts/monogram-bitmap.json` for example.

Render helpers include `draw_text` and `measure_text`.

## Usage

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
