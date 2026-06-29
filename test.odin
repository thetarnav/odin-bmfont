#+test
#+private
package bmfont

import "core:testing"
import "core:os"
import "core:fmt"
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
		testing.expectf(t, false,
			"snapshot mismatch for %s — re-run with -update if the change is intentional",
			snapshot_path,
		)
	}
}

bytes_equal :: proc(a, b: []u8) -> bool {
	if len(a) != len(b) do return false
	for i in 0..<len(a) {
		if a[i] != b[i] do return false
	}
	return true
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
