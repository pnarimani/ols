package ols_testing

import "core:log"
// ============================================================================
// Diff-based Code Action Testing
// ============================================================================
//
// A more robust way to test code actions using a unified diff-like format.
// Instead of manually specifying line numbers and positions, write the source
// with inline diff markers showing the expected transformation.
//
// Format:
//   - Lines starting with " " (space) or no prefix: common to before/after
//   - Lines starting with "-": only in "before" (will be removed/changed)
//   - Lines starting with "+": only in "after" (will be added)
//   - Selection markers {<} and {>} go in the "before" lines (- or common)
//
// Example:
//   ```
//   package test
//   main :: proc() {
//   -	x := {<}a + b{>}
//   +	extracted := a + b
//   +	x := extracted
//   }
//   ```
//
// This will:
//   1. Parse to get "before" code with selection markers
//   2. Parse to get expected "after" code
//   3. Apply the code action to "before"
//   4. Verify result matches "after"

import "core:fmt"
import "core:strings"
import "core:testing"

import "src:analysis"
import "src:common"
import "src:documents"
import "src:server"

// Test a code action using diff format.
// The diff_source contains:
//   - Lines starting with "-": before only (contain selection markers {<} {>})
//   - Lines starting with "+": after only (expected result)
//   - Lines starting with " " or no prefix: common to both
expect_code_action_diff :: proc(
	t: ^testing.T,
	action_name: string,
	diff_source: string,
	packages: []FileInPackage = {},
) {
	files := make([dynamic]FileInPackage, context.temp_allocator)
	append(&files, FileInPackage{source = diff_source})
	for pkg in packages {
		append(&files, pkg)
	}
	src := Source {
		files = files[:],
	}

	parse_ok := parse_diff_source(&src)
	if !parse_ok {
		testing.expect(t, false, "Failed to parse diff source")
		return
	}

	setup(&src)
	defer teardown(&src)

	primary := get_primary_file(&src)
	input_range := build_action_range(&src)
	actions, ok := server.get_code_actions(&primary.doc_ctx, input_range, &src.config)
	if !ok {
		testing.expect(t, false, "Failed to get code actions")
		return
	}

	// Find the requested action
	for action in actions {
		if action.title != action_name do continue

		all_match := true

		// Check edits for all files
		for &file in src.files {
			encoded_path := common.path_to_uri(file.fullpath, context.temp_allocator)
			edits, found := action.edit.changes[encoded_path]

			if found {
				source := string(file.doc_ctx.text)
				actual_after := apply_text_edits(source, edits)

				normalized_expected := normalize_source(file.source_expected)
				normalized_actual := normalize_source(actual_after)

				if normalized_expected != normalized_actual {
					testing.expectf(
						t,
						false,
						"\nCode action result mismatch for file %s.\n\nExpected:\n%s\n\nActual:\n%s",
						file.filename,
						normalized_expected,
						normalized_actual,
					)
					all_match = false
				}
			} else {
				// No edits for this file - it should remain unchanged
				normalized_expected := normalize_source(file.source_expected)
				normalized_before := normalize_source(file.source)
				if normalized_expected != normalized_before {
					testing.expectf(
						t,
						false,
						"\nFile %s expected changes but got none.\n\nExpected:\n%s\n\nActual:\n%s",
						file.filename,
						normalized_expected,
						normalized_before,
					)
					all_match = false
				}
			}
		}

		if all_match {
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

// Parses diff-formatted sources in all files of the Source.
// For each file, parses the diff from file.source:
//   - Puts "before" code (with markers) back into file.source
//   - Puts "after" code (expected result) into file.source_expected
// Returns: success
@(private = "file")
parse_diff_source :: proc(src: ^Source) -> bool {
	for &file in src.files {
		before_builder := strings.builder_make(context.temp_allocator)
		after_builder := strings.builder_make(context.temp_allocator)

		lines := strings.split_lines(file.source, context.temp_allocator)

		for line in lines {
			if len(line) == 0 {
				strings.write_string(&before_builder, "\n")
				strings.write_string(&after_builder, "\n")
				continue
			}

			first_char := line[0]
			rest := line[1:] if len(line) > 1 else ""

			switch first_char {
			case '-':
				strings.write_string(&before_builder, rest)
				strings.write_string(&before_builder, "\n")
			case '+':
				strings.write_string(&after_builder, rest)
				strings.write_string(&after_builder, "\n")
			case ' ':
				strings.write_string(&before_builder, rest)
				strings.write_string(&before_builder, "\n")
				strings.write_string(&after_builder, rest)
				strings.write_string(&after_builder, "\n")
			case:
				strings.write_string(&before_builder, line)
				strings.write_string(&before_builder, "\n")
				strings.write_string(&after_builder, line)
				strings.write_string(&after_builder, "\n")
			}
		}

		before_code := strings.to_string(before_builder)
		after_code := strings.to_string(after_builder)

		after_code, _ = strings.replace_all(after_code, "{<}", "", context.temp_allocator)
		after_code, _ = strings.replace_all(after_code, "{>}", "", context.temp_allocator)
		after_code, _ = strings.replace_all(after_code, "{*}", "", context.temp_allocator)

		file.source = strings.clone(before_code, context.temp_allocator)
		file.source_expected = strings.clone(after_code, context.temp_allocator)
	}

	return true
}

// Apply text edits to source code and return the result.
// Edits are sorted and applied from end to start to preserve positions.
@(private = "file")
apply_text_edits :: proc(source: string, edits: []server.TextEdit) -> string {
	if len(edits) == 0 {
		return source
	}

	// Sort edits by position (reverse order so we can apply from end to start)
	sorted_edits := make([]server.TextEdit, len(edits), context.temp_allocator)
	copy(sorted_edits, edits)

	// Simple bubble sort (edits are usually small in number)
	for i in 0 ..< len(sorted_edits) {
		for j in i + 1 ..< len(sorted_edits) {
			// Compare by line first, then by character
			if sorted_edits[j].range.start.line > sorted_edits[i].range.start.line ||
			   (sorted_edits[j].range.start.line == sorted_edits[i].range.start.line &&
					   sorted_edits[j].range.start.character > sorted_edits[i].range.start.character) {
				sorted_edits[i], sorted_edits[j] = sorted_edits[j], sorted_edits[i]
			}
		}
	}

	result := strings.clone(source, context.temp_allocator)

	// Apply edits from end to start to preserve positions
	for edit in sorted_edits {
		start_offset := position_to_offset(result, edit.range.start)
		end_offset := position_to_offset(result, edit.range.end)

		if start_offset < 0 || end_offset < 0 || start_offset > len(result) || end_offset > len(result) {
			continue
		}

		// Build new string: before + newText + after
		new_result := strings.concatenate(
			{result[:start_offset], edit.newText, result[end_offset:]},
			context.temp_allocator,
		)
		result = new_result
	}

	return result
}

// Convert a Position to a byte offset in the source.
@(private = "file")
position_to_offset :: proc(source: string, pos: common.Position) -> int {
	line := 0
	offset := 0

	for offset < len(source) {
		if line == pos.line {
			// Found the line, now add character offset
			char_offset := 0
			for offset + char_offset < len(source) && char_offset < pos.character {
				if source[offset + char_offset] == '\n' {
					break
				}
				char_offset += 1
			}
			return offset + char_offset
		}

		if source[offset] == '\n' {
			line += 1
		}
		offset += 1
	}

	// If we're looking for a position past the end, return end
	if line == pos.line {
		return offset
	}

	return -1
}

@(private = "file")
normalize_source :: proc(source: string) -> string {
	source_no_tabs, _ := strings.replace_all(source, "\t", "    ", context.temp_allocator)

	lines := strings.split_lines(source_no_tabs, context.temp_allocator)
	builder := strings.builder_make(context.temp_allocator)

	// Find the last non-empty line to avoid trailing blank lines
	last_non_empty := len(lines) - 1
	for last_non_empty >= 0 && strings.trim_space(lines[last_non_empty]) == "" {
		last_non_empty -= 1
	}

	for i in 0 ..= last_non_empty {
		trimmed := strings.trim_right_space(lines[i])
		strings.write_string(&builder, trimmed)
		if i < last_non_empty {
			strings.write_string(&builder, "\n")
		}
	}

	return strings.to_string(builder)
}

// ============================================================================
// Multi-file Code Action Testing
// ============================================================================
//
// Test code actions that affect multiple files using the Source struct.
//
// Usage:
//   - main_diff: The main file where the code action is triggered (with diff markers)
//   - main_pkg: Optional package name for the main file (if different from "test")
//   - package_diffs: Additional files that may be affected
//     - pkg: Package name (use "test" for same package as main)
//     - filename: Optional filename (for same-package different file)
//     - source: Diff-formatted source code
//
// Each source follows the same diff format as expect_code_action_diff.

// Test a code action that affects multiple files.
// main_diff contains the main file's diff source (where action is triggered)
// main_pkg is optional - if the main file is in a different package than "test"
// package_diffs contains additional files as Package_Diff structs
expect_code_action_diff_multi_file :: proc(
	t: ^testing.T,
	action_name: string,
	main_diff: string,
	extra_files: []FileInPackage = {},
) {
	files := make([dynamic]FileInPackage, context.temp_allocator)
	append(&files, FileInPackage{source = main_diff})
	for extra_file in extra_files {
		append(&files, extra_file)
	}
	src := Source {
		files = files[:],
	}

	parse_ok := parse_diff_source(&src)
	if !parse_ok {
		testing.expect(t, false, "Failed to parse diff sources")
		return
	}

	setup(&src)
	defer teardown(&src)

	primary := get_primary_file(&src)
	input_range := build_action_range(&src)
	actions, ok := server.get_code_actions(&primary.doc_ctx, input_range, &src.config)
	if !ok {
		testing.expect(t, false, "Failed to get code actions")
		return
	}

	// Find the requested action
	for action in actions {
		if action.title != action_name do continue

		all_match := true

		// Check edits for all files
		for &file in src.files {
			encoded_path := common.path_to_uri(file.fullpath, context.temp_allocator)
			edits, found := action.edit.changes[encoded_path]

			if found {
				source := string(file.doc_ctx.text)
				actual_after := apply_text_edits(source, edits)
				normalized_expected := normalize_source(file.source_expected)
				normalized_actual := normalize_source(actual_after)

				if normalized_expected != normalized_actual {
					testing.expectf(
						t,
						false,
						"\nCode action result mismatch for package '%s' file '%s'.\n\nExpected:\n%s\n\nActual:\n%s\n--------",
						file.pkg,
						file.filename,
						normalized_expected,
						normalized_actual,
					)
					all_match = false
				}
			} else {
				// No edits for this file - it should remain unchanged
				normalized_expected := normalize_source(file.source_expected)
				normalized_before := normalize_source(file.source)
				if normalized_expected != normalized_before {
					testing.expectf(
						t,
						false,
						"\nPackage '%s' file '%s' expected changes but got none.\n\nExpected:\n%s\n\nActual:\n%s\n--------",
						file.pkg,
						file.filename,
						normalized_expected,
						normalized_before,
					)
					all_match = false
				}
			}
		}

		if all_match {
			return
		}
	}

	testing.expectf(t, false, "Action '%s' not found", action_name)
}
