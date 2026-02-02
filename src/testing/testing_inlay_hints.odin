package ols_testing

import "core:fmt"
import "core:log"
import "core:strings"
import "core:testing"
import "src:common"
import "src:server"

expect_inlay_hints :: proc(t: ^testing.T, src: ^Source) {

	src_builder := strings.builder_make(context.temp_allocator)
	expected_hints := make([dynamic]server.InlayHint, context.temp_allocator)

	HINT_OPEN :: "[["
	HINT_CLOSE :: "]]"

	{
		last, line, col: int
		saw_brackets: bool
		for i := 0; i < len(src.main); i += 1 {
			if saw_brackets {
				if i + 1 < len(src.main) && src.main[i:][:len(HINT_CLOSE)] == HINT_CLOSE {
					saw_brackets = false
					hint_str := src.main[last:i]
					last = i + len(HINT_CLOSE)
					i = last - 1
					append(
						&expected_hints,
						server.InlayHint{position = {line, col}, label = hint_str, kind = .Parameter},
					)
				}
			} else {
				if i + 1 < len(src.main) && src.main[i:][:len(HINT_OPEN)] == HINT_OPEN {
					strings.write_string(&src_builder, src.main[last:i])
					saw_brackets = true
					last = i + len(HINT_OPEN)
					i = last - 1
				} else if src.main[i] == '\n' {
					line += 1
					col = 0
				} else {
					col += 1
				}
			}
		}

		if saw_brackets {
			log.error("Unclosed inlay hint marker")
			return
		}

		strings.write_string(&src_builder, src.main[last:len(src.main)])
	}

	src.main = strings.to_string(src_builder)

	setup(src)
	defer teardown(src)

	symbols_and_nodes := server.resolve_entire_file(src.doc_ctx)

	range := common.Range {
		end = {line = 9000000},
	} //should be enough
	hints, hints_ok := server.get_inlay_hints(src.doc_ctx, range, symbols_and_nodes, &src.config)
	if !hints_ok {
		log.error("Failed get_inlay_hints")
		return
	}

	testing.expectf(
		t,
		len(expected_hints) == len(hints),
		"Expected %d inlay hints, but received %d",
		len(expected_hints),
		len(hints),
	)

	lines := strings.split_lines(src.main, context.temp_allocator)

	get_source_line_with_hint :: proc(lines: []string, hint: server.InlayHint) -> string {
		line := lines[hint.position.line] if hint.position.line >= 0 && hint.position.line < len(lines) else ""
		if hint.position.character >= 0 && hint.position.character <= len(line) {
			builder := strings.builder_make(context.temp_allocator)
			strings.write_string(&builder, line[:hint.position.character])
			strings.write_string(&builder, HINT_OPEN)
			strings.write_string(&builder, hint.label)
			strings.write_string(&builder, HINT_CLOSE)
			strings.write_string(&builder, line[hint.position.character:])
			return strings.to_string(builder)
		}
		return ""
	}

	for i in 0 ..< max(len(expected_hints), len(hints)) {
		expected_text := "---"
		actual_text := "---"

		if i < len(expected_hints) {
			expected := expected_hints[i]
			expected_line := get_source_line_with_hint(lines, expected)
			expected_text = fmt.tprintf(
				"\"%s\" at (%d, %d): \"%s\"",
				expected.label,
				expected.position.line,
				expected.position.character,
				expected_line,
			)
		}

		if i < len(hints) {
			actual := hints[i]
			actual_line := get_source_line_with_hint(lines, actual)
			actual_text = fmt.tprintf(
				"\"%s\" at (%d, %d): \"%s\"",
				actual.label,
				actual.position.line,
				actual.position.character,
				actual_line,
			)
		}

		if i >= len(expected_hints) {
			log.errorf("[%d]: Unexpected inlay hint\nExpected: %s\nActual:   %s", i, expected_text, actual_text)
		} else if i >= len(hints) {
			log.errorf("[%d]: Missing inlay hint\nExpected: %s\nActual:   %s", i, expected_text, actual_text)
		} else if expected_hints[i] != hints[i] {
			log.errorf("[%d]: Inlay hint mismatch\nExpected: %s\nActual:   %s", i, expected_text, actual_text)
		}
	}
}
