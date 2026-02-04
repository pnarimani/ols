package ols_testing

import "core:log"
import "core:testing"
import "src:common"
import "src:server"

expect_prepare_rename_range :: proc(t: ^testing.T, src: ^Source, expect_range: common.Range) {
	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	range, ok := server.get_prepare_rename(&primary.doc_ctx, primary.position)
	if !ok {
		log.error("Failed to find range")
	}

	if range != expect_range {
		ok = false
		log.errorf("Failed to match with range: %v", expect_range)
	}

	if !ok {
		log.error("Received: %v\n", range)
	}
}

// Test rename using diff format.
// The diff_source contains:
//   - Lines starting with "-": before only (contain cursor marker {*})
//   - Lines starting with "+": after only (expected result after rename)
//   - Lines starting with " " or no prefix: common to both
// The new_name parameter specifies what the symbol should be renamed to.
expect_rename_diff :: proc(t: ^testing.T, new_name: string, src: ^Source) {
	if !parse_diff_source(src) {
		testing.expect(t, false, "Failed to parse diff source")
		return
	}

	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	workspace_edit, ok := server.get_rename(&primary.doc_ctx, new_name, primary.position)
	if !ok {
		testing.expect(t, false, "Failed to get rename edits")
		return
	}

	// Apply edits to each file and store in source_actual
	for &file in src.files {
		encoded_path := common.path_to_uri(file.fullpath, context.temp_allocator)
		edits, found := workspace_edit.changes[encoded_path]

		if found {
			source := string(file.doc_ctx.text)
			file.source_actual = apply_text_edits(source, edits)
		} else {
			// No edits for this file - use original source without markers
			file.source_actual = file.source
		}
	}

	// Verify all files match expected results
	assert_files_match_expected(t, src)
}
