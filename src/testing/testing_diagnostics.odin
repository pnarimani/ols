package ols_testing

import "core:log"
import "core:strings"
import "core:testing"

import "src:common"
import "src:diagnostics"
import "src:server"

// Test that a specific diagnostic is present at the exact range marked by {<} and {>} in the source
expect_diagnostic_at :: proc(t: ^testing.T, src: ^Source, code: string, message_contains: string = "") {
	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	encoded_path := common.path_to_uri(primary.document.filepath, context.temp_allocator)

	range := common.Range {
		start = primary.position,
		end   = primary.end_position,
	}

	// Collect all diagnostics with matching code for error reporting
	found := false
	found_diagnostics := make([dynamic]server.Diagnostic, context.temp_allocator)

	// Query the persistent diagnostic store for .Hint diagnostics
	diag_arr := diagnostics.get_diagnostics_for_path(encoded_path, .Hint, context.temp_allocator)
	for diag in diag_arr {
		if diag.code == code {
			append(&found_diagnostics, diag)

			range_matches := diag.range.start == range.start && diag.range.end == range.end
			message_matches := message_contains == "" || strings.contains(diag.message, message_contains)

			if range_matches && message_matches {
				found = true
				break
			}
		}
	}

	if !found {
		if len(found_diagnostics) == 0 {
			testing.expectf(t, false, "Expected diagnostic '%s' at range (%d:%d)-(%d:%d) not found. No diagnostics with code '%s' exist.",
				code,
				range.start.line, range.start.character,
				range.end.line, range.end.character,
				code)
		} else {
			log.errorf("Expected diagnostic '%s' at range (%d:%d)-(%d:%d)",
				code,
				range.start.line, range.start.character,
				range.end.line, range.end.character)
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

	primary := get_primary_file(src)
	path := primary.document.filepath
	encoded_path := common.path_to_uri(primary.document.filepath, context.temp_allocator)
	
	// Query the persistent diagnostic store for .Hint diagnostics
	diag_arr := diagnostics.get_diagnostics_for_path(encoded_path, .Hint, context.temp_allocator)
	for diag in diag_arr {
		if diag.code == code {
			log.errorf("Expected no diagnostic with code '%s', but found one: %s", code, diag.message)
			testing.expect(t, false)
			return
		}
	}
}
