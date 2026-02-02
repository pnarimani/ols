package tests

import "core:testing"

import test "src:testing"

INLINE_PROC_ACTION :: "Inline Proc"

// ============================================================================
// Tests for inlining from a procedure call (simple single-return bodies)
// ============================================================================

@(test)
action_inline_proc_simple_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

add :: proc(a, b: int) -> int {
	return a + b
}

main :: proc() {
-	x := {*}add(1, 2)
+	x := 1 + 2
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_call_with_complex_args :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

compute :: proc(n: int) -> int {
	return n * 2
}

main :: proc() {
	x := 10
-	y := {*}compute(x + 5)
+	y := (x + 5) * 2
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_void_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

do_nothing :: proc() {
}

main :: proc() {
-	{*}do_nothing()
+
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_call_as_argument :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

square :: proc(n: int) -> int {
	return n * n
}

print_int :: proc(n: int) {
}

main :: proc() {
-	print_int({*}square(4))
+	print_int(4 * 4)
}
`,
		INLINE_PROC_ACTION,
	)
}

// ============================================================================
// Multi-Statement body inlining
// ============================================================================

@(test)
action_inline_proc_multi_statement_body :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

compute_sum :: proc(a, b: int) -> int {
	sum := a + b
	return sum
}

main :: proc() {
-	x := {*}compute_sum(3, 4)
+	sum := 3 + 4
+	x := sum
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_multi_statement_body_void :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

log_message :: proc(msg: string) {
	prefix := "[LOG]: "
	full_msg := prefix + msg
	println(full_msg)
}

main :: proc() {
-	{*}log_message("Hello, World!")
+	prefix := "[LOG]: "
+	full_msg := prefix + "Hello, World!"
+	println(full_msg)
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_multi_statement_body_call_as_argument :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

compute :: proc(n: int) -> int {
	calc := n * 2
	return calc + 3
}

print_int :: proc(n: int) {
}

main :: proc() {
-	print_int({*}compute(5))
+	calc := 5 * 2
+	print_int(calc + 3)
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_multi_statement_body_name_conflict :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

something :: proc(n: int) -> int {
	temp := n * 2
	return temp + 1
}

main :: proc() {
	temp := 10
-	x := {*}something(temp)
+	_something_temp := temp * 2
+	x := _something_temp + 1
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_multi_statement_body_with_defer :: proc(t: ^testing.T) {
    test.expect_code_action_diff(
        t,
        `package test
cleanup :: proc() {
    println("Cleaning up")
}

something :: proc() {

}

do_work :: proc() {
    something()
    defer cleanup()
    println("Doing work")
}

main :: proc() {
    before()
-   {*}do_work()
+   {
+       something()
+       defer cleanup()
+       println("Doing work")
+   }
    after()
}
`,
        INLINE_PROC_ACTION,
    )
}

@(test)
action_inline_proc_multi_statement_body_with_double_nested_defer :: proc(t: ^testing.T) {
    test.expect_code_action_diff(
        t,
        `package test
cleanup :: proc() {
    println("Cleaning up")
}

something :: proc() {

}

do_work :: proc() {
    defer cleanup()
    println("Doing work")
    {
        defer something()
        println("Nested work")
    }
    println("after scope")
}

main :: proc() {
    before()
-   {*}do_work()
+   {
+       defer cleanup()
+       println("Doing work")
+       {
+           defer something()
+           println("Nested work")
+       }
+       println("after scope")
+   }
    after()
}
`,
        INLINE_PROC_ACTION,
    )
}


@(test)
action_inline_proc_multi_statement_body_with_nested_defer :: proc(t: ^testing.T) {
    test.expect_code_action_diff(
        t,
        `package test
cleanup :: proc() {
    println("Cleaning up")
}

something :: proc() {

}

do_work :: proc() {
    println("Doing work")
    {
        defer something()
        println("Nested work")
    }
    println("after scope")
}

main :: proc() {
    before()
-   {*}do_work()
+   println("Doing work")
+   {
+       defer something()
+       println("Nested work")
+   }
+   println("after scope")
    after()
}
`,
        INLINE_PROC_ACTION,
    )
}

// ============================================================================
// Tests for inlining from a procedure definition
// ============================================================================

@(test)
action_inline_proc_from_definition_single_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

-{*}helper :: proc(n: int) -> int {
-	return n + 1
-}

main :: proc() {
-	x := helper(10)
+	x := 10 + 1
}
`,
		INLINE_PROC_ACTION,
	)
}

@(test)
action_inline_proc_from_definition_multiple_calls :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

-{*}double :: proc(n: int) -> int {
-	return n * 2
-}

main :: proc() {
-	a := double(5)
+	a := 5 * 2
-	b := double(10)
+	b := 10 * 2
-	c := double(a)
+	c := a * 2
}
`,
		INLINE_PROC_ACTION,
	)
}

// ============================================================================
// Tests for restrictions
// ============================================================================

@(test)
action_inline_proc_recursive :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

factorial :: proc(n: int) -> int {
	if n <= 1 {
		return 1
	}
	return n * factorial(n - 1)
}

main :: proc() {
	x := {*}factorial(5)
}
`},
		extra_files = {},
	}

	// Recursive procedures have multiple returns - not supported
	test.expect_action_excludes(t, &source, {INLINE_PROC_ACTION})
}

@(test)
action_inline_proc_no_body :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

foreign_proc :: proc(x: int) -> int ---

main :: proc() {
	x := {*}foreign_proc(5)
}
`},
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {INLINE_PROC_ACTION})
}

@(test)
action_inline_proc_not_on_call :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

foo :: proc() -> int {
	return 42
}

main :: proc() {
	x := {*}123
}
`},
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {INLINE_PROC_ACTION})
}

@(test)
action_inline_proc_from_definition_no_calls :: proc(t: ^testing.T) {
	source := test.Source {
		main = {source = `package test

{*}unused :: proc(n: int) -> int {
	return n
}

main :: proc() {
	x := 10
}
`},
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {INLINE_PROC_ACTION})
}
