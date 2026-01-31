package ols_testing

import "core:log"
import "core:strings"
import "core:testing"

import "src:common"
import "src:server"

// Test that a specific diagnostic is present at the exact range marked by {<} and {>} in the source
expect_diagnostic_at :: proc(t: ^testing.T, src: ^Source, code: string, message_contains: string = "") {
	setup(src)
	defer teardown(src)

	path := src.document.uri.path
	uri := common.create_uri(path, context.temp_allocator)

	expected_range := common.Range {
		start = src.position,
		end   = src.end_position,
	}

	// Collect all diagnostics with matching code for error reporting
	found := false
	found_diagnostics := make([dynamic]server.Diagnostic, context.temp_allocator)

	diag_map := &server.diagnostics[.Hint]
	if diag_arr, ok := diag_map[uri.uri]; ok {
		for diag in diag_arr {
			if diag.code == code {
				append(&found_diagnostics, diag)

				range_matches := diag.range.start == expected_range.start && diag.range.end == expected_range.end
				message_matches := message_contains == "" || strings.contains(diag.message, message_contains)

				if range_matches && message_matches {
					found = true
					break
				}
			}
		}
	}

	if !found {
		if len(found_diagnostics) == 0 {
			testing.expectf(t, false, "Expected diagnostic '%s' at range (%d:%d)-(%d:%d) not found. No diagnostics with code '%s' exist.",
				code,
				expected_range.start.line, expected_range.start.character,
				expected_range.end.line, expected_range.end.character,
				code)
		} else {
			log.errorf("Expected diagnostic '%s' at range (%d:%d)-(%d:%d)",
				code,
				expected_range.start.line, expected_range.start.character,
				expected_range.end.line, expected_range.end.character)
			log.errorf("Found %d diagnostic(s) with code '%s':", len(found_diagnostics), code)
			for diag, i in found_diagnostics {
				log.errorf("  [%d] range (%d:%d)-(%d:%d): %s",
					i,
					diag.range.start.line, diag.range.start.character,
					diag.range.end.line, diag.range.end.character,
					diag.message)
			}
			testing.expect(t, false, "Diagnostic found but at wrong position")
		}
	}
}

// Test that no diagnostic with specific code is present
expect_no_diagnostic :: proc(t: ^testing.T, src: ^Source, code: string) {
	setup(src)
	defer teardown(src)

	path := src.document.uri.path
	uri := common.create_uri(path, context.temp_allocator)
	
	// Check the diagnostics map for our document
	diag_map := &server.diagnostics[.Hint]
	if diag_arr, ok := diag_map[uri.uri]; ok {
		for diag in diag_arr {
			if diag.code == code {
				log.errorf("Expected no diagnostic with code '%s', but found one: %s", code, diag.message)
				testing.expect(t, false)
				return
			}
		}
	}
}
