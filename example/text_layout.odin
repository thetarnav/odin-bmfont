package example

// Sequential text layout helpers built on top of k2.draw_text and k2.measure_text.
//
// `Text_Cursor` carries the y position of the next line. `draw_line` advances it past
// a single line of text; `draw_paragraph` word-wraps a multi-line string at
// `max_width` and advances the cursor past every line.

import k2 "./karl2d"

Vec2 :: k2.Vec2

// A draw cursor. `pos` is the top-left of the next line to draw. `extra_gap` is the
// extra vertical space inserted between lines (on top of the font's own line height).
Text_Cursor :: struct {
	pos:       Vec2,
	extra_gap: f32,
}

// Vertical advance for one line of `font` at `font_size`. Uses k2.measure_text with a
// single tall character so it works for both k2's static and dynamic font paths.
line_height :: proc(font: k2.Font, font_size: f32) -> f32 {
	return k2.measure_text("M", font_size, font).y
}

// Draw one line of text at the cursor and advance the cursor's y past it. The cursor's
// x is not changed.
draw_line :: proc(
	font:      k2.Font,
	text:      string,
	font_size: f32,
	color:     k2.Color,
	cursor:    ^Text_Cursor,
) {
	k2.draw_text(text, cursor.pos, font_size, color, font)
	cursor.pos.y += line_height(font, font_size) + cursor.extra_gap
}

// Word-wrap `text` to fit lines within `max_width` and draw each line. The cursor's y
// is advanced past every line.
//
// Hard newlines in the input force a line break (and the word before them is flushed
// to its own line). A single word wider than `max_width` is placed on its own line
// regardless. Leading spaces at the start of each emitted line are trimmed.
draw_paragraph :: proc(
	font:      k2.Font,
	text:      string,
	font_size: f32,
	max_width: f32,
	color:     k2.Color,
	cursor:    ^Text_Cursor,
) {
	space_w := k2.measure_text(" ", font_size, font).x
	lh      := line_height(font, font_size)

	current := make([dynamic]u8, context.temp_allocator)
	defer delete(current)
	line_w: f32 = 0

	i, n := 0, len(text)
	for i < n {
		// Read one word (non-space, non-newline).
		word_start := i
		for i < n && text[i] != ' ' && text[i] != '\n' {
			i += 1
		}
		word := text[word_start:i]

		// Hard newline: flush the line with the current word, then start fresh.
		if i < n && text[i] == '\n' {
			append(&current, word)
			if len(current) > 0 {
				k2.draw_text(string(current[:]), cursor.pos, font_size, color, font)
				cursor.pos.y += lh + cursor.extra_gap
				clear(&current)
			}
			line_w = 0
			i += 1
			continue
		}

		// Skip spaces (they belong to the inter-word gap, not the next word).
		for i < n && text[i] == ' ' {
			i += 1
		}

		if len(current) == 0 {
			// First word on a line — always fits (single oversized word goes on
			// its own line; the wrap step below catches the next one).
			append(&current, word)
			line_w = k2.measure_text(word, font_size, font).x
		} else if line_w + space_w + k2.measure_text(word, font_size, font).x > max_width {
			// Adding this word would overflow the line: emit what we have, start
			// a new line with the word.
			k2.draw_text(string(current[:]), cursor.pos, font_size, color, font)
			cursor.pos.y += lh + cursor.extra_gap
			clear(&current)
			append(&current, word)
			line_w = k2.measure_text(word, font_size, font).x
		} else {
			// Fits on the current line.
			append(&current, ' ')
			append(&current, word)
			line_w += space_w + k2.measure_text(word, font_size, font).x
		}
	}

	if len(current) > 0 {
		k2.draw_text(string(current[:]), cursor.pos, font_size, color, font)
		cursor.pos.y += lh + cursor.extra_gap
	}
}
