package ols_testing

import "core:log"
import "core:testing"
import "src:common"
import "src:server"

// Build the input range from source position markers
@(private)
build_action_range :: proc(src: ^Source) -> common.Range {
	if src.has_range {
		return common.Range{start = src.position, end = src.end_position}
	}
	return common.Range{start = src.position, end = src.position}
}

expect_no_action :: proc(t: ^testing.T, main: string, action_name: string, packages: []Package = {}) {
	src := Source {
		main     = main,
		packages = packages,
	}

	setup(&src)
	defer teardown(&src)

	input_range := build_action_range(&src)
	actions, ok := server.get_code_actions(src.doc_ctx, input_range, &src.config)
	if !ok {
		// No actions returned is fine for this test
		return
	}

	// Check that the action_name is NOT present
	for action in actions {
		if action.title == action_name {
			testing.expectf(t, false, "Action '%s' should not be available, but was found", action_name)
			return
		}
	}

	// Test passes - action was not found
}

expect_action :: proc(t: ^testing.T, src: ^Source, expect_action_names: []string) {
	setup(src)
	defer teardown(src)

	input_range := build_action_range(src)
	actions, ok := server.get_code_actions(src.doc_ctx, input_range, &src.config)
	if !ok {
		log.error("Failed to find actions")
	}

	if len(expect_action_names) == 0 && len(actions) > 0 {
		log.errorf("Expected empty actions, but received %v", actions)
	}

	flags := make([]int, len(expect_action_names), context.temp_allocator)

	for name, i in expect_action_names {
		for action, j in actions {
			if action.title == name {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected action %v, but received %v", expect_action_names[i], actions)
		}
	}
}

expect_action_excludes :: proc(t: ^testing.T, src: ^Source, excluded_action_names: []string) {
	setup(src)
	defer teardown(src)

	input_range := build_action_range(src)
	actions, ok := server.get_code_actions(src.doc_ctx, input_range, &src.config)
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

expect_action_with_edit :: proc(t: ^testing.T, src: ^Source, action_name: string, expected_texts: ..string) {
	setup(src)
	defer teardown(src)

	input_range := build_action_range(src)
	actions, ok := server.get_code_actions(src.doc_ctx, input_range, &src.config)
	if !ok {
		log.error("Failed to find actions")
		return
	}

	for action in actions {
		if action.title == action_name {
			// Get the text edits for the document
			encoded_path := common.make_encoded_path(src.doc_ctx.filepath, context.temp_allocator)
			if edits, found := action.edit.changes[encoded_path]; found {
				if len(edits) != len(expected_texts) {
					log.errorf("Expected %d edits but got %d", len(expected_texts), len(edits))
					return
				}

				for expected, i in expected_texts {
					actual := edits[i].newText
					testing.expectf(
						t,
						actual == expected,
						"\nEdit [%d] mismatch.\nExpected:\n%s\n\nGot:\n%s",
						i,
						expected,
						actual,
					)
				}
				return
			}
			log.errorf("Action '%s' found but has no edits", action_name)
			return
		}
	}

	log.errorf("Action '%s' not found in actions: %v", action_name, actions)
}

// Like expect_action_with_edit but also checks that an edit is placed at or after a specific line
expect_action_with_edit_at_line :: proc(
	t: ^testing.T,
	src: ^Source,
	action_name: string,
	edit_index: int,
	min_line: int,
	expected_texts: ..string,
) {
	setup(src)
	defer teardown(src)

	input_range := build_action_range(src)
	actions, ok := server.get_code_actions(src.doc_ctx, input_range, &src.config)
	if !ok {
		log.error("Failed to find actions")
		testing.expect(t, false, "Failed to find actions")
		return
	}

	for action in actions {
		if action.title == action_name {
			// Get the text edits for the document
			encoded_path := common.make_encoded_path(src.doc_ctx.filepath, context.temp_allocator)
			if edits, found := action.edit.changes[encoded_path]; found {
				if len(edits) != len(expected_texts) {
					testing.expectf(t, false, "Expected %d edits but got %d", len(expected_texts), len(edits))
					return
				}

				// Check edit positions
				if edit_index < len(edits) {
					actual_line := edits[edit_index].range.start.line
					testing.expectf(
						t,
						actual_line >= min_line,
						"\nEdit [%d] placed at wrong line.\nExpected: line >= %d\nGot: line %d",
						edit_index,
						min_line,
						actual_line,
					)
				}

				// Check edit content
				for expected, i in expected_texts {
					actual := edits[i].newText
					testing.expectf(
						t,
						actual == expected,
						"\nEdit [%d] mismatch.\nExpected:\n%s\n\nGot:\n%s",
						i,
						expected,
						actual,
					)
				}
				return
			}
			log.errorf("Action '%s' found but has no edits", action_name)
			testing.expect(t, false, "Action found but has no edits")
			return
		}
	}

	testing.expectf(t, false, "Action '%s' not found", action_name)
}
