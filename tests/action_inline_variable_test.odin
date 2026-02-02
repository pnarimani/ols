package tests

import "core:testing"

import test "src:testing"

INLINE_VARIABLE_ACTION :: "Inline Variable"

// ============================================================================
// Basic inlining tests
// ============================================================================

@(test)
action_inline_variable_simple :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	{*}x := 10
-	y := x + 5
+	y := 10 + 5
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_expression :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
-	{*}sum := a + b
-	result := sum * 2
+	result := (a + b) * 2
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_multiple_usages :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	{*}x := 5
-	a := x
-	b := x + 1
-	c := x * 2
+	a := 5
+	b := 5 + 1
+	c := 5 * 2
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_call_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

get_value :: proc() -> int { return 42 }

main :: proc() {
-	{*}val := get_value()
-	result1 := val + 1
-	result2 := val + 2
+	result1 := get_value() + 1
+	result2 := get_value() + 2
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_in_function_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

print :: proc(n: int) {}

main :: proc() {
-	{*}x := 10
-	print(x)
+	print(10)
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_binary_expr_no_parens_needed :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
-	{*}x := a + 2
-	y := x
+	y := a + 2
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_in_return :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

compute :: proc() -> int {
-	{*}result := 42
-	return result
+	return 42
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_in_condition :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	{*}flag := true
-	if flag {
+	if true {
		x := 1
	}
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_in_loop :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	{*}limit := 10
-	for i := 0; i < limit; i += 1 {
+	for i := 0; i < 10; i += 1 {
		x := i
	}
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

// ============================================================================
// Usage-site inlining tests - cursor on variable usage instead of declaration
// ============================================================================

@(test)
action_inline_variable_from_usage_single :: proc(t: ^testing.T) {
	// When cursor is on the only usage, inline it and delete the declaration
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	x := 10
-	y := {*}x + 5
+	y := 10 + 5
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_from_usage_multiple_first :: proc(t: ^testing.T) {
	// When cursor is on one of multiple usages, only inline that usage
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	a := {*}x
+	a := 5
	b := x + 1
	c := x * 2
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_from_usage_multiple_last :: proc(t: ^testing.T) {
	// Inline only the last usage
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	a := x
	b := x + 1
-	c := {*}x * 2
+	c := 5 * 2
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_from_usage_with_parens :: proc(t: ^testing.T) {
	// Inline from usage site with parentheses needed
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
	sum := a + b
	result := sum * 2
-	other := {*}sum / 3
+	other := (a + b) / 3
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_from_usage_in_condition :: proc(t: ^testing.T) {
	// Inline from usage in a condition
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	flag := true
-	if {*}flag {
+	if true {
		x := 1
	}
	other := flag
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

@(test)
action_inline_variable_from_usage_in_call :: proc(t: ^testing.T) {
	// Inline from usage in a function call
	test.expect_code_action_diff(
		t,
		`package test

print :: proc(n: int) {}

main :: proc() {
	x := 10
-	print({*}x)
+	print(10)
	y := x + 1
}
`,
		INLINE_VARIABLE_ACTION,
	)
}

// ============================================================================
// Tests for restrictions - action should NOT be available
// ============================================================================

@(test)
action_inline_variable_reassigned :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	{*}x := 10
	x = 20
	y := x
}
`,
		extra_files = {},
	}

	// Variable is reassigned - cannot inline
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_no_usages :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	{*}x := 10
}
`,
		extra_files = {},
	}

	// Variable has no usages - action not useful
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_not_on_variable :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := {*}10
}
`,
		extra_files = {},
	}

	// Cursor not on variable name
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_procedure_decl :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	{*}helper :: proc() {}
	helper()
}
`,
		extra_files = {},
	}

	// Cannot inline procedure declarations
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_used_in_loop_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	{*}sum := 0
	for i in 0..<10 {
		sum += i
	}
}
`,
		extra_files = {},
	}

	// Variable is modified in loop
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_outside_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

{*}GLOBAL :: 42

main :: proc() {
	x := GLOBAL
}
`,
		extra_files = {},
	}

	// Global constants - not inside a procedure
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_multi_var_decl_first :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	{*}a, b := 1, 2
	x := a + b
}
`,
		extra_files = {},
	}

	// Multiple variables in one declaration - not supported
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_multi_var_decl_second :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	a, {*}b := 1, 2
	x := a + b
}
`,
		extra_files = {},
	}

	// Multiple variables in one declaration - not supported
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

// ============================================================================
// Tests for usage-site restrictions - same rules apply
// ============================================================================

@(test)
action_inline_variable_from_usage_reassigned :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := 10
	x = 20
	y := {*}x
}
`,
		extra_files = {},
	}

	// Variable is reassigned - cannot inline from usage site either
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_from_usage_mutated_in_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	sum := 0
	for i in 0..<10 {
		sum += i
	}
	result := {*}sum
}
`,
		extra_files = {},
	}

	// Variable is modified - cannot inline from usage site
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}

@(test)
action_inline_variable_from_usage_multi_var_decl :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	a, b := 1, 2
	x := {*}a + b
}
`,
		extra_files = {},
	}

	// Multiple variables in one declaration - not supported from usage site either
	test.expect_action_excludes(t, &source, {INLINE_VARIABLE_ACTION})
}
