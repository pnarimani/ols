package ols_testing

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
expect_code_action_diff :: proc(t: ^testing.T, diff_source: string, action_name: string, packages: []Package = {}) {
	before_code, expected_after, parse_ok := parse_diff_source(diff_source)
	if !parse_ok {
		testing.expect(t, false, "Failed to parse diff source")
		return
	}

	// Create source with the "before" code
	src := Source {
		main     = before_code,
		packages = packages,
	}

	setup(&src)
	defer teardown(&src)

	input_range := build_action_range(&src)
	actions, ok := server.get_code_actions(src.doc_ctx, input_range, &src.config)
	if !ok {
		testing.expect(t, false, "Failed to get code actions")
		return
	}

	// Find the requested action
	for action in actions {
		if action.title != action_name do continue
		edits, found := action.edit.changes[src.doc_ctx.uri.uri]
		if !found {
			testing.expect(t, false, "Action found but has no edits")
			return
		}

		source := string(src.doc_ctx.text)

		actual_after := apply_text_edits(source, edits)

		normalized_expected := normalize_source(expected_after)
		normalized_actual := normalize_source(actual_after)

		if normalized_expected != normalized_actual {
			testing.expectf(
				t,
				false,
				"\nCode action result mismatch.\n\nExpected:\n%s\n\nActual:\n%s",
				normalized_expected,
				normalized_actual,
			)
		}
		return
	}

	testing.expectf(t, false, "Action '%s' not found", action_name)
}

// Parses a diff-formatted source into before and after code.
// Returns: before_code (with markers), after_code (without markers), success
@(private = "file")
parse_diff_source :: proc(diff_source: string) -> (before: string, after: string, ok: bool) {
	before_builder := strings.builder_make(context.temp_allocator)
	after_builder := strings.builder_make(context.temp_allocator)

	lines := strings.split_lines(diff_source, context.temp_allocator)

	for line in lines {
		if len(line) == 0 {
			// Empty line goes to both
			strings.write_string(&before_builder, "\n")
			strings.write_string(&after_builder, "\n")
			continue
		}

		first_char := line[0]
		rest := line[1:] if len(line) > 1 else ""

		switch first_char {
		case '-':
			// Only in "before"
			strings.write_string(&before_builder, rest)
			strings.write_string(&before_builder, "\n")
		case '+':
			// Only in "after"
			strings.write_string(&after_builder, rest)
			strings.write_string(&after_builder, "\n")
		case ' ':
			// Common to both (space prefix)
			strings.write_string(&before_builder, rest)
			strings.write_string(&before_builder, "\n")
			strings.write_string(&after_builder, rest)
			strings.write_string(&after_builder, "\n")
		case:
			// No prefix - treat as common (for convenience)
			strings.write_string(&before_builder, line)
			strings.write_string(&before_builder, "\n")
			strings.write_string(&after_builder, line)
			strings.write_string(&after_builder, "\n")
		}
	}

	before_code := strings.to_string(before_builder)
	after_code := strings.to_string(after_builder)

	// Remove selection markers from after_code (they shouldn't be there but just in case)
	after_code, _ = strings.replace_all(after_code, "{<}", "", context.temp_allocator)
	after_code, _ = strings.replace_all(after_code, "{>}", "", context.temp_allocator)
	after_code, _ = strings.replace_all(after_code, "{*}", "")

	return before_code, after_code, true
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

// Extended Package type for multi-file testing that includes expected result
Package_Diff :: struct {
	pkg:      string, // Package name
	filename: string, // Optional: filename within package
	source:   string, // Diff-formatted source (before code with markers)
}

// Test a code action that affects multiple files.
// main_diff contains the main file's diff source (where action is triggered)
// main_pkg is optional - if the main file is in a different package than "test"
// package_diffs contains additional files as Package_Diff structs
expect_code_action_diff_multi_file :: proc(
	t: ^testing.T,
	main_diff: string,
	action_name: string,
	package_diffs: []Package_Diff = {},
) {
	// Parse main file diff
	main_before, main_expected, main_ok := parse_diff_source(main_diff)
	if !main_ok {
		testing.expect(t, false, "Failed to parse main file diff source")
		return
	}

	// Build packages for Source from package_diffs (using before code)
	packages := make([]Package, len(package_diffs), context.temp_allocator)
	package_expected := make([]string, len(package_diffs), context.temp_allocator)

	for pkg_diff, i in package_diffs {
		before, expected, ok := parse_diff_source(pkg_diff.source)
		if !ok {
			testing.expectf(t, false, "Failed to parse diff for package '%s'", pkg_diff.pkg)
			return
		}
		packages[i] = Package {
			pkg      = pkg_diff.pkg,
			filename = pkg_diff.filename,
			source   = before,
		}
		package_expected[i] = expected
	}

	src := Source {
		main     = main_before,
		packages = packages,
	}

	setup(&src)
	defer teardown(&src)

	input_range := build_action_range(&src)
	actions, ok := server.get_code_actions(src.doc_ctx, input_range, &src.config)
	if !ok {
		testing.expect(t, false, "Failed to get code actions")
		return
	}

	// Find the requested action
	for action in actions {
		if action.title != action_name do continue

		// Check main file edits
		all_match := true
		main_uri := src.doc_ctx.uri.uri

		edits, found := action.edit.changes[main_uri]
		if found {
			actual_after := apply_text_edits(main_before, edits)
			normalized_expected := normalize_source(main_expected)
			normalized_actual := normalize_source(actual_after)

			if normalized_expected != normalized_actual {
				testing.expectf(
					t,
					false,
					"\nCode action result mismatch for main file.\n\nExpected:\n%s\n\nActual:\n%s",
					normalized_expected,
					normalized_actual,
				)
				all_match = false
			}
		} else {
			// No edits for main file - it should remain unchanged
			normalized_expected := normalize_source(main_expected)
			normalized_before := normalize_source(main_before)
			if normalized_expected != normalized_before {
				testing.expectf(
					t,
					false,
					"\nMain file expected changes but got none.\n\nExpected:\n%s\n\nActual:\n%s",
					normalized_expected,
					normalized_before,
				)
				all_match = false
			}
		}

		// Check package file edits
		for pkg_diff, i in package_diffs {
			pkg := packages[i]
			expected := package_expected[i]

			// Build expected URI for this file
			filename := pkg.filename if pkg.filename != "" else "package"
			uri := common.create_uri(
				fmt.tprintf("test/%s/%s.odin", pkg.pkg, filename),
				context.temp_allocator,
			).uri

			pkg_edits, pkg_found := action.edit.changes[uri]
			if pkg_found {
				actual_after := apply_text_edits(pkg.source, pkg_edits)
				normalized_expected := normalize_source(expected)
				normalized_actual := normalize_source(actual_after)

				if normalized_expected != normalized_actual {
					testing.expectf(
						t,
						false,
						"\nCode action result mismatch for package '%s' file '%s'.\n\nExpected:\n%s\n\nActual:\n%s",
						pkg.pkg,
						filename,
						normalized_expected,
						normalized_actual,
					)
					all_match = false
				}
			} else {
				// No edits for this file - it should remain unchanged
				normalized_expected := normalize_source(expected)
				normalized_before := normalize_source(pkg.source)
				if normalized_expected != normalized_before {
					testing.expectf(
						t,
						false,
						"\nPackage '%s' file '%s' expected changes but got none.\n\nExpected:\n%s\n\nActual:\n%s",
						pkg.pkg,
						filename,
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