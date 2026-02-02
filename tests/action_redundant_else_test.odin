package tests

import "core:testing"

import test "src:testing"
import "src:server"

REDUNDANT_ELSE_ACTION :: "Remove redundant else"

@(test)
action_redundant_else_with_return_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	x := 5
	if x > 0 {
		foo()
		return
	} {*}else {
		bar()
	}
}
`},
		extra_files = {},
	}

	expected := `if x > 0 {
		foo()
		return
	}
	bar()`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

@(test)
action_redundant_else_with_return_multiple_stmts :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	x := 5
	if x > 0 {
		foo()
		return
	} {*}else {
		bar()
		baz()
	}
}
`},
		extra_files = {},
	}

	expected := `if x > 0 {
		foo()
		return
	}
	bar()
	baz()`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

// Tests for redundant else removal with break statement in loops

@(test)
action_redundant_else_with_break_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	for i in 0..<10 {
		if i > 5 {
			foo()
			break
		} {*}else {
			bar()
		}
	}
}
`},
		extra_files = {},
	}

	expected := `if i > 5 {
			foo()
			break
		}
		bar()`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

// Tests for redundant else removal with continue statement in loops

@(test)
action_redundant_else_with_continue_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	for i in 0..<10 {
		if i == 3 {
			continue
		} {*}else {
			process(i)
		}
	}
}
`},
		extra_files = {},
	}

	expected := `if i == 3 {
			continue
		}
		process(i)`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

// Negative tests - should NOT offer the action

@(test)
action_redundant_else_not_on_if :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	x := 5
	{*}if x > 0 {
		foo()
		return
	} else {
		bar()
	}
}
`},
		extra_files = {},
	}

	// Should not offer Remove redundant else when cursor is on if (only on else)
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_redundant_else_not_on_non_if :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	x :={*} 5
}
`},
		extra_files = {},
	}

	// Should not have the action when not on an if statement
	test.expect_action(t, &source, {})
}

@(test)
action_redundant_else_no_else_clause :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x{*} > 0 {
		foo()
		return
	}
}
`},
		extra_files = {},
	}

	// Should not have Remove redundant else action when there's no else clause
	// But Invert if is still available
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_redundant_else_no_terminating_stmt :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
		foo()
	} {*}else {
		bar()
	}
}
`},
		extra_files = {},
	}

	// Should not have Remove redundant else action when if block doesn't end with return/break/continue
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_redundant_else_break_outside_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
		foo()
		break
	} {*}else {
		bar()
	}
}
`},
		extra_files = {},
	}

	// Break outside a loop is not valid, so we shouldn't offer Remove redundant else
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_redundant_else_continue_outside_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
		foo()
		continue
	} {*}else {
		bar()
	}
}
`},
		extra_files = {},
	}

	// Continue outside a loop is not valid for Remove redundant else
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

// Edge case tests

@(test)
action_redundant_else_else_if_chain_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
		foo()
		return
	} {*}else if x < 0 {
		bar()
	} else {
		baz()
	}
}
`},
		extra_files = {},
	}

	expected := `if x > 0 {
		foo()
		return
	}
	if x < 0 {
		bar()
	} else {
		baz()
	}`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

@(test)
action_redundant_else_else_if_chain_simple_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
		foo()
		return
	} {*}else if x < 0 {
		bar()
	}
}
`},
		extra_files = {},
	}

	expected := `if x > 0 {
		foo()
		return
	}
	if x < 0 {
		bar()
	}`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

@(test)
action_redundant_else_nested_if :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	for i in 0..<10 {
		if x > 0 {
			if y > 0 {
				foo()
				break
			} {*}else {
				bar()
			}
		}
	}
}
`},
		extra_files = {},
	}

	// Should offer action for nested if with break in a loop
	test.expect_action(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_with_init_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x := foo(); x > 0 {
		bar()
		return
	} {*}else {
		baz()
	}
}
`},
		extra_files = {},
	}

	expected := `if x := foo(); x > 0 {
		bar()
		return
	}
	baz()`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

@(test)
action_redundant_else_in_switch :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	switch x {
	case 1:
		if y > 0 {
			foo()
			break
		} {*}else {
			bar()
		}
	}
}
`},
		extra_files = {},
	}

	// Break in a switch case is valid, should offer action
	test.expect_action(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_return_not_last :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
		return
		foo() // unreachable
	} {*}else {
		bar()
	}
}
`},
		extra_files = {},
	}

	// Return is not the last statement, so no Remove redundant else
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_redundant_else_empty_if_body :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
	} {*}else {
		bar()
	}
}
`},
		extra_files = {},
	}

	// Empty if body - no terminating statement, so no Remove redundant else
	test.expect_action(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_redundant_else_empty_else_body_edit :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	if x > 0 {
		foo()
		return
	} {*}else {
	}
}
`},
		extra_files = {},
	}

	expected := `if x > 0 {
		foo()
		return
	}`

	test.expect_action_with_edit(t, &source, REDUNDANT_ELSE_ACTION, expected)
}

// Test with labeled break/continue

@(test)
action_redundant_else_labeled_break :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	outer: for i in 0..<10 {
		for j in 0..<10 {
			if j > 5 {
				foo()
				break outer
			} {*}else {
				bar()
			}
		}
	}
}
`},
		extra_files = {},
	}

	// Labeled break still breaks out of a loop
	test.expect_action(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_labeled_continue :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	outer: for i in 0..<10 {
		for j in 0..<10 {
			if j > 5 {
				foo()
				continue outer
			} {*}else {
				bar()
			}
		}
	}
}
`},
		extra_files = {},
	}

	// Labeled continue still continues a loop
	test.expect_action(t, &source, {REDUNDANT_ELSE_ACTION})
}

// Test with fallthrough in switch

@(test)
action_redundant_else_with_fallthrough :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

main :: proc() {
	switch x {
	case 1:
		if y > 0 {
			foo()
			fallthrough
		} {*}else {
			bar()
		}
	case 2:
		baz()
	}
}
`},
		extra_files = {},
	}

	// Fallthrough transfers control, so else is redundant
	test.expect_action(t, &source, {REDUNDANT_ELSE_ACTION})
}
