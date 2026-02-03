package ols_testing

import "core:testing"
import "src:common"
import "src:server"

expect_semantic_tokens :: proc(t: ^testing.T, src: ^Source, expected: []server.SemanticToken) {
	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	resolve_flag: server.ResolveReferenceFlag
	symbols_and_nodes := server.resolve_entire_file(&primary.doc_ctx, resolve_flag)

	range := common.Range {
		end = {line = 9000000},
	} //should be enough
	tokens := server.get_semantic_tokens(&primary.doc_ctx, range, symbols_and_nodes)

	testing.expectf(
		t,
		len(expected) == len(tokens),
		"\nExpected %d tokens, but received %d",
		len(expected),
		len(tokens),
	)

	for i in 0 ..< min(len(expected), len(tokens)) {
		e, a := expected[i], tokens[i]
		testing.expectf(
			t,
			e == a,
			"\n[%d]: Expected \n(%d, %d, %d, %v, %w)\nbut received\n(%d, %d, %d, %v, %w)",
			i,
			e.delta_line,
			e.delta_char,
			e.len,
			e.type,
			e.modifiers,
			a.delta_line,
			a.delta_char,
			a.len,
			a.type,
			a.modifiers,
		)
	}
}
