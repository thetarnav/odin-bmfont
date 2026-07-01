#+test
#+private
package bmfont

import "core:testing"
import "core:log"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:path/filepath"
import "core:encoding/json"

SNAPSHOTS_DIR :: "tests/snapshots"

Font_Fixture :: struct {
	name:      string,
	path:      string,
	encoding:  Format,
}

FONT_FIXTURES :: []Font_Fixture{
	{name = "minogram_6x10", path = "fonts/minogram_6x10.xml",  encoding = .XML},
	{name = "square_6x6",    path = "fonts/square_6x6.xml",     encoding = .XML},
	{name = "round_6x6",     path = "fonts/round_6x6.xml",      encoding = .XML},
	{name = "thick_8x8",     path = "fonts/thick_8x8.xml",      encoding = .XML},
	{name = "WhitePeaberry", path = "fonts/WhitePeaberry.xml",  encoding = .XML},
}

// WhitePeaberry is shipped in three equivalent wire formats (XML, TXT). The
// snapshot is taken from the XML version; the variant test below parses the other
// two and asserts they produce the same `Font`.
WHITEPEABERRY_VARIANTS :: []Font_Fixture{
	{name = "xml", path = "fonts/WhitePeaberry.xml", encoding = .XML},
	{name = "txt", path = "fonts/WhitePeaberry.txt", encoding = .Text},
}

// True when `BMFONT_UPDATE_SNAPSHOTS=1` is in the environment — the snapshot files
// should be (re)written instead of compared. Odin's testing runner rejects unknown
// CLI flags, so the update switch is communicated via the environment instead.
should_update_snapshots :: proc() -> bool {
	value, _ := os.lookup_env_alloc("BMFONT_UPDATE_SNAPSHOTS", context.temp_allocator)
	return value != "" && value != "0" && value != "false"
}

// Pretty-print the same way every run so snapshot diffs are stable.
marshal_options :: json.Marshal_Options {
	spec             = .JSON,
	pretty           = true,
	use_spaces       = true,
	spaces           = 2,
	sort_maps_by_key = true,
	use_enum_names   = true,
}

// Load a fixture and write/compare its snapshot.
run_snapshot :: proc(t: ^testing.T, fix: Font_Fixture) {

	bytes, read_err := os.read_entire_file(fix.path, context.temp_allocator)
	if read_err != nil {
		testing.expectf(t, false, "could not read fixture %s: %v", fix.path, read_err)
		return
	}

	// Parse into the temp allocator so the per-fixture strings/glyphs/ranges are
	// freed automatically at the end of the test frame — no destroy_font needed.
	font, ferr := load_bmfont(string(bytes), fix.encoding, context.temp_allocator)
	if ferr != nil {
		testing.expectf(t, false, "load_bmfont(%s, %v): %v", fix.path, fix.encoding, ferr)
		return
	}

	snapshot, jerr := json.marshal(font, marshal_options, context.temp_allocator)
	if jerr != nil {
		testing.expectf(t, false, "json.marshal(%s): %v", fix.path, jerr)
		return
	}

	snapshot_path, join_err := filepath.join({SNAPSHOTS_DIR, fmt.tprintf("%s.json", fix.name)})
	if join_err != nil {
		testing.expectf(t, false, "filepath.join: %v", join_err)
		return
	}
	defer delete(snapshot_path)

	if should_update_snapshots() {
		werr := os.write_entire_file(snapshot_path, snapshot)
		if werr != nil {
			testing.expectf(t, false, "could not write snapshot %s: %v", snapshot_path, werr)
			return
		}
		fmt.printf("  wrote %s (%d bytes)\n", snapshot_path, len(snapshot))
		return
	}

	expected, read_err_2 := os.read_entire_file(snapshot_path, context.temp_allocator)
	if read_err_2 != nil {
		testing.expectf(t, false,
			"snapshot %s not found — re-run with -update to create it (e.g. `make test-update`)",
			snapshot_path,
		)
		return
	}

	if !bytes_equal(expected, snapshot) {
		// Build the full diagnostic message first and hand it to a single log.error
		// call so the test runner emits it as one record (and not interleaved with
		// other log lines from the test framework).
		diff := simple_line_diff(string(expected), string(snapshot))
		msg := fmt.tprintf(
			"snapshot mismatch for %s — re-run with -update if the change is intentional\n\n%s",
			snapshot_path,
			diff,
		)
		log.error(msg)
	}
}

bytes_equal :: proc(a, b: []u8) -> bool {
	if len(a) != len(b) do return false
	for i in 0..<len(a) {
		if a[i] != b[i] do return false
	}
	return true
}

// Basic line-by-line diff between two strings. Lines that are equal are skipped;
// differing lines are emitted with `  ` (unchanged prefix reused), `- ` (old), and
// `+ ` (new) markers. Output is truncated to a sane size so a wildly-different
// snapshot doesn't flood the test log. Good enough to spot which fields changed
// (a JSON diff where line 50 says `"stretch_h": 100` vs `"stretch_h": 999` is
// exactly what a human eyeballs anyway).
simple_line_diff :: proc(old_text, new_text: string) -> string {
	MAX_DIFF_LINES :: 64

	old_lines := strings.split(old_text, "\n", context.temp_allocator)
	new_lines := strings.split(new_text, "\n", context.temp_allocator)

	buf: [dynamic]u8
	defer delete(buf)

	emit :: proc(b: ^[dynamic]u8, prefix, line: string) {
		append(b, prefix)
		append(b, line)
		append(b, '\n')
	}

	line_count: int
	truncated := false

	i: int
	for i < len(old_lines) {
		if line_count >= MAX_DIFF_LINES {
			truncated = true
			break
		}
		if i < len(new_lines) && old_lines[i] == new_lines[i] {
			i += 1
			continue
		}
		emit(&buf, "- ", old_lines[i])
		if i < len(new_lines) {
			emit(&buf, "+ ", new_lines[i])
		}
		line_count += 1
		i += 1
	}

	for j in len(old_lines)..<len(new_lines) {
		if line_count >= MAX_DIFF_LINES {
			truncated = true
			break
		}
		emit(&buf, "+ ", new_lines[j])
		line_count += 1
	}

	if truncated {
		emit(&buf, "  ", fmt.tprintf("... diff truncated at %d lines ...", MAX_DIFF_LINES))
	}

	return string(buf[:])
}

// Marshal a Font the same way the snapshot test does, so we can byte-compare variant
// parses against the canonical XML snapshot.
font_to_snapshot_bytes :: proc(font: ^Font, allocator := context.temp_allocator) -> []u8 {
	data, err := json.marshal(font, marshal_options, allocator)
	if err != nil { return nil }
	return data
}

@test
test_snapshots :: proc(t: ^testing.T) {
	if err := os.make_directory_all(SNAPSHOTS_DIR); err != nil && err != .Exist {
		testing.expectf(t, false, "could not create %s: %v", SNAPSHOTS_DIR, err)
		return
	}

	for fix in FONT_FIXTURES {
		fmt.printf("snapshot: %s\n", fix.name)
		run_snapshot(t, fix)
	}
}

@test
test_whitepeaberry_encodings_match :: proc(t: ^testing.T) {
	// Load all three encodings and verify they produce the same `Font` value.
	// The XML version is the canonical one — its snapshot is the reference.
	// All allocations live on the temp allocator and are freed at end of frame.
	xml_bytes, read_err := os.read_entire_file("fonts/WhitePeaberry.xml", context.temp_allocator)
	if read_err != nil {
		testing.expectf(t, false, "could not read WhitePeaberry.xml")
		return
	}
	xml_font, err := load_bmfont_xml(string(xml_bytes), context.temp_allocator)
	if err != nil {
		testing.expectf(t, false, "XML parse failed: %v", err)
		return
	}
	xml_snapshot := font_to_snapshot_bytes(&xml_font)

	for fix in WHITEPEABERRY_VARIANTS {
		bytes, read_err_2 := os.read_entire_file(fix.path, context.temp_allocator)
		if read_err_2 != nil {
			testing.expectf(t, false, "could not read %s", fix.path)
			return
		}
		font, err := load_bmfont(string(bytes), fix.encoding, context.temp_allocator)
		if err != nil {
			testing.expectf(t, false, "load_bmfont(%s, %v): %v", fix.path, fix.encoding, err)
			return
		}
		// Don't append to `loaded` — we let the temp allocator clean up at end of
		// frame, which is what the leak-free test expects.
		fmt.printf("whitepeaberry variant %s: %d bytes\n", fix.encoding, len(font.glyphs))

		// Each variant should produce the same snapshot as the XML one.
		variant_snapshot := font_to_snapshot_bytes(&font)
		if !bytes_equal(xml_snapshot, variant_snapshot) {
			diff := simple_line_diff(string(xml_snapshot), string(variant_snapshot))
			msg := fmt.tprintf(
				"WhitePeaberry .%s differs from .xml — re-run with -update if the change is intentional\n\n%s",
				encoding_name(fix.encoding),
				diff,
			)
			log.error(msg)
		}
	}
}

// `fmt.tprintf("%v", Encoding)` would print the variant's integer value, which is
// not a useful label. Provide a short tag for log messages instead.
encoding_name :: proc(e: Format) -> string {
	switch e {
	case .XML: return "xml"
	case .Text: return "txt"
	}
	return "?"
}
