package ols_testing

import "core:fmt"
import "core:strings"
import "core:log"
import "core:testing"
import "src:common"
import "src:server"

// Test a code action using diff format.
// The diff_source contains:
//   - Lines starting with "-": before only (contain selection markers {<} {>})
//   - Lines starting with "+": after only (expected result)
//   - Lines starting with " " or no prefix: common to both
expect_code_action_diff :: proc(
	t: ^testing.T,
	action_name: string,
	src: ^Source,
) {
	if !parse_diff_source(src){
		testing.expect(t, false, "Failed to parse diff source")
		return
	}

	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	input_range := build_action_range(src)
	actions, ok := server.get_code_actions(&primary.doc_ctx, input_range, &src.config)
	if !ok {
		testing.expect(t, false, "Failed to get code actions")
		return
	}

	// Find the requested action
	for action in actions {
		if action.title != action_name do continue

		// Store actual results in source_actual for each file
		for &file in src.files {
			encoded_path := common.path_to_uri(file.fullpath, context.temp_allocator)
			edits, found := action.edit.changes[encoded_path]

			if found {
				source := string(file.doc_ctx.text)
				file.source_actual = apply_text_edits(source, edits)
			} else {
				// No edits for this file - it should remain unchanged
				file.source_actual = file.source
			}
		}

		// Verify all files match expected results
		if assert_files_match_expected(t, src) {
			return
		}
	}

	sb := strings.builder_make(context.temp_allocator)
	strings.write_string(&sb, "Available actions:\n")
	for action in actions {
		strings.write_string(&sb, fmt.tprintf(" - %s\n", action.title))
	}
	strings.write_string(&sb, "----")

	testing.expectf(t, false, "Action '%s' not found.\n%s", action_name, strings.to_string(sb))
}

expect_action_excludes :: proc(t: ^testing.T, src: ^Source, excluded_action_names: []string) {
	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	input_range := build_action_range(src)
	actions, ok := server.get_code_actions(&primary.doc_ctx, input_range, &src.config)
	if !ok {
		log.error("Failed to find actions")
	}

	for excluded_name in excluded_action_names {
		for action in actions {
			if action.title == excluded_name {
				log.errorf("Expected action '%v' to NOT be present, but it was found", excluded_name)
			}
		}
	}
}

// Build the input range from source position markers
@(private)
build_action_range :: proc(src: ^Source) -> common.Range {
	primary := get_primary_file(src)
	if primary.has_range {
		return common.Range{start = primary.position, end = primary.end_position}
	}
	return common.Range{start = primary.position, end = primary.position}
}