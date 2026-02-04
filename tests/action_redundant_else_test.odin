package tests

import "core:testing"

import "src:server"
import test "src:testing"

REDUNDANT_ELSE_ACTION :: "Remove redundant else"

@(test)
action_redundant_else_with_return_edit :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	x := 5
-	if x > 0 {
-		foo()
-		return
-	} {*}else {
-		bar()
-	}
+	if x > 0 {
+		foo()
+		return
+	}
+	bar()
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_with_return_multiple_stmts :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	x := 5
-	if x > 0 {
-		foo()
-		return
-	} {*}else {
-		bar()
-		baz()
-	}
+	if x > 0 {
+		foo()
+		return
+	}
+	bar()
+	baz()
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

// Tests for redundant else removal with break statement in loops

@(test)
action_redundant_else_with_break_edit :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	for i in 0..<10 {
-		if i > 5 {
-			foo()
-			break
-		} {*}else {
-			bar()
-		}
+		if i > 5 {
+			foo()
+			break
+		}
+		bar()
	}
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

// Tests for redundant else removal with continue statement in loops

@(test)
action_redundant_else_with_continue_edit :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	for i in 0..<10 {
-		if i == 3 {
-			continue
-		} {*}else {
-			process(i)
-		}
+		if i == 3 {
+			continue
+		}
+		process(i)
	}
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

// Negative tests - should NOT offer the action

@(test)
action_redundant_else_not_on_if :: proc(t: ^testing.T) {
	// This test just verifies that we can detect an if statement with redundant else
	// The action is offered for the entire if statement, not just when cursor is on else
	// Since this is a valid redundant else case, the action should be offered
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	x := 5
-	{*}if x > 0 {
-		foo()
-		return
-	} else {
-		bar()
-	}
+	if x > 0 {
+		foo()
+		return
+	}
+	bar()
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_not_on_non_if :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
	x :={*} 5
}
`}},
	}
	// Should not have the action when not on an if statement
	test.expect_action_excludes(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_no_else_clause :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
	if x{*} > 0 {
		foo()
		return
	}
}
`}},
	}

	// Should not have Remove redundant else action when there's no else clause
	// But Invert if is still available
	test.expect_action_excludes(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_no_terminating_stmt :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
	if x > 0 {
		foo()
	} {*}else {
		bar()
	}
}
`}},
	}

	// Should not have Remove redundant else action when if block doesn't end with return/break/continue
	test.expect_action_excludes(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_break_outside_loop :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
	if x > 0 {
		foo()
		break
	} {*}else {
		bar()
	}
}
`}},
	}

	// Break outside a loop is not valid, so we shouldn't offer Remove redundant else
	test.expect_action_excludes(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_continue_outside_loop :: proc(t: ^testing.T) {
	source := test.Source {
		files = {
			{source = `package test

main :: proc() {
	if x > 0 {
		foo()
		continue
	} {*}else {
		bar()
	}
}
`},
		},
	}

	// Continue outside a loop is not valid for Remove redundant else
	test.expect_action_excludes(t, &source, {REDUNDANT_ELSE_ACTION})
}

// Edge case tests

@(test)
action_redundant_else_else_if_chain_edit :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
-	if x > 0 {
-		foo()
-		return
-	} {*}else if x < 0 {
-		bar()
-	} else {
-		baz()
-	}
+	if x > 0 {
+		foo()
+		return
+	}
+	if x < 0 {
+		bar()
+	} else {
+		baz()
+	}
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_else_if_chain_simple_edit :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
-	if x > 0 {
-		foo()
-		return
-	} {*}else if x < 0 {
-		bar()
-	}
+	if x > 0 {
+		foo()
+		return
+	}
+	if x < 0 {
+		bar()
+	}
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_nested_if :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	for i in 0..<10 {
		if x > 0 {
-			if y > 0 {
-				foo()
-				break
-			} {*}else {
-				bar()
-			}
+			if y > 0 {
+				foo()
+				break
+			}
+			bar()
		}
	}
}
`,
			},
		},
	}
	// Should offer action for nested if with break in a loop
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_with_init_edit :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
-	if x := foo(); x > 0 {
-		bar()
-		return
-	} {*}else {
-		baz()
-	}
+	if x := foo(); x > 0 {
+		bar()
+		return
+	}
+	baz()
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_in_switch :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	switch x {
	case 1:
-		if y > 0 {
-			foo()
-			break
-		} {*}else {
-			bar()
-		}
+		if y > 0 {
+			foo()
+			break
+		}
+		bar()
	}
}
`,
			},
		},
	}
	// Break in a switch case is valid, should offer action
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_return_not_last :: proc(t: ^testing.T) {
	source := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	if x > 0 {
		return
		foo() // unreachable
	} {*}else {
		bar()
	}
}
`,
			},
		},
	}

	// Return is not the last statement, so no Remove redundant else
	test.expect_action_excludes(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_empty_if_body :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
	if x > 0 {
	} {*}else {
		bar()
	}
}
`}},
	}

	// Empty if body - no terminating statement, so no Remove redundant else
	test.expect_action_excludes(t, &source, {REDUNDANT_ELSE_ACTION})
}

@(test)
action_redundant_else_empty_else_body_edit :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
-	if x > 0 {
-		foo()
-		return
-	} {*}else {
-	}
+	if x > 0 {
+		foo()
+		return
+	}
}
`,
			},
		},
	}
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

// Test with labeled break/continue

@(test)
action_redundant_else_labeled_break :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	outer: for i in 0..<10 {
		for j in 0..<10 {
-			if j > 5 {
-				foo()
-				break outer
-			} {*}else {
-				bar()
-			}
+			if j > 5 {
+				foo()
+				break outer
+			}
+			bar()
		}
	}
}
`,
			},
		},
	}
	// Labeled break still breaks out of a loop
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

@(test)
action_redundant_else_labeled_continue :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	outer: for i in 0..<10 {
		for j in 0..<10 {
-			if j > 5 {
-				foo()
-				continue outer
-			} {*}else {
-				bar()
-			}
+			if j > 5 {
+				foo()
+				continue outer
+			}
+			bar()
		}
	}
}
`,
			},
		},
	}
	// Labeled continue still continues a loop
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}

// Test with fallthrough in switch

@(test)
action_redundant_else_with_fallthrough :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{
				source = `package test

main :: proc() {
	switch x {
	case 1:
-		if y > 0 {
-			foo()
-			fallthrough
-		} {*}else {
-			bar()
-		}
+		if y > 0 {
+			foo()
+			fallthrough
+		}
+		bar()
	case 2:
		baz()
	}
}
`,
			},
		},
	}
	// Fallthrough transfers control, so else is redundant
	test.expect_code_action_diff(t, REDUNDANT_ELSE_ACTION, &src)
}
