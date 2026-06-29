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

FONT_FIXTURES :: []struct{name, path: string}{
	{name = "minogram_6x10", path = "fonts/minogram_6x10.xml"},
	{name = "square_6x6",    path = "fonts/square_6x6.xml"},
	{name = "round_6x6",     path = "fonts/round_6x6.xml"},
	{name = "thick_8x8",     path = "fonts/thick_8x8.xml"},
	{name = "WhitePeaberry", path = "fonts/WhitePeaberry.xml"},
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

// Run the snapshot test for a single fixture. When `-update` is set, write the freshly
// marshalled JSON to the snapshot path. Otherwise compare against the on-disk snapshot
// and report a clear message if it is missing or differs.
run_snapshot :: proc(t: ^testing.T, name, xml_path: string) {
	xml_bytes, read_err := os.read_entire_file(xml_path, context.temp_allocator)
	if read_err != nil {
		testing.expectf(t, false, "could not read fixture %s: %v", xml_path, read_err)
		return
	}

	font, ferr := load_font_from_bytes(xml_bytes, context.temp_allocator)
	if ferr != nil {
		testing.expectf(t, false, "load_font_from_bytes(%s): %v", xml_path, ferr)
		return
	}

	snapshot, jerr := json.marshal(font, marshal_options, context.temp_allocator)
	if jerr != nil {
		testing.expectf(t, false, "json.marshal(%s): %v", xml_path, jerr)
		return
	}

	snapshot_path, join_err := filepath.join({SNAPSHOTS_DIR, fmt.tprintf("%s.json", name)})
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

	// Walk both line slices by index. Where they agree, drop the line; where they
	// disagree, emit both with `- ` and `+ ` markers.
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

	// Trailing lines only present in `new`.
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

@test
test_snapshots :: proc(t: ^testing.T) {
	if err := os.make_directory_all(SNAPSHOTS_DIR); err != nil && err != .Exist {
		testing.expectf(t, false, "could not create %s: %v", SNAPSHOTS_DIR, err)
		return
	}

	for fix in FONT_FIXTURES {
		fmt.printf("snapshot: %s\n", fix.name)
		run_snapshot(t, fix.name, fix.path)
	}
}
