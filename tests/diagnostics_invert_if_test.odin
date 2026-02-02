package tests

import "core:testing"

import test "src:testing"

INVERT_IF_DIAGNOSTIC_CODE :: "InvertIf"

// Test: negated condition with else should suggest inversion
@(test)
diagnostic_invert_if_negated_condition :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := true
	if {<}!x{>} {
		y := 1
	} else {
		z := 2
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "negation")
}

// Test: complex if body with no else (guard clause opportunity)
@(test)
diagnostic_invert_if_guard_clause_opportunity :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := get_value()
	if {<}x > 0{>} {
		step1()
		step2()
		if nested_condition() {
			step3()
		}
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "guard clause")
}

// Test: else body is early exit, if body is complex
@(test)
diagnostic_invert_if_early_exit_pattern :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := get_value()
	if {<}x > 0{>} {
		step1()
		step2()
		step3()
	} else {
		return
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "readability")
}

// Test: simple if without else should NOT suggest inversion
@(test)
diagnostic_invert_if_no_suggestion_simple :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := get_value()
	if x > 0 {
		do_something()
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: else-if chain should NOT suggest inversion
@(test)
diagnostic_invert_if_no_suggestion_else_if_chain :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := get_value()
	if x > 0 {
		foo()
	} else if x < 0 {
		bar()
	} else {
		baz()
	}

	for !rl.WindowShouldClose() {
		mouse_position := rl.GetMousePosition()

		if rl.IsKeyPressed(.SPACE) {
			springs.bump(&scale_spring, rl.Vector3{2.5, 2.5, 0})
			springs.bump(&rotation_spring, rl.Vector3{0, 0, 30})
			springs.bump(&fade_spring, -10.7)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

@(test)
diagnostic_invert_if_no_suggestion_statements_after_if :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	for !rl.WindowShouldClose() {
		mouse_position := rl.GetMousePosition()

		if rl.IsKeyPressed(.SPACE) {
			springs.bump(&scale_spring, rl.Vector3{2.5, 2.5, 0})
			springs.bump(&rotation_spring, rl.Vector3{0, 0, 30})
			springs.bump(&fade_spring, -10.7)
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: balanced branches should NOT suggest inversion
@(test)
diagnostic_invert_if_no_suggestion_balanced :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := get_value()
	if x > 0 {
		foo()
		bar()
	} else {
		baz()
		qux()
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

@(test)
diagnostic_invert_if_no_suggestion_remaining_statements :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

with_return_value :: proc() -> int {
	x := get_value()
	if x > 0 {
		foo()
		bar()

		if another_condition() {
			if nested () {
				return 1
			}
		}
	}

	if final_check() {
		qux()
		bruh()
		something()
	}

	return 2
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: feature disabled should not produce diagnostics
@(test)
diagnostic_invert_if_disabled :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := get_value()
	if !x {
		handle_error()
	} else {
		do_work()
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = false},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: nested if inside loop body should NOT suggest guard clause
// (guard clause pattern only makes sense at top level)
@(test)
diagnostic_invert_if_nested_in_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	for item in items {
		if condition {
			step1()
			step2()
			step3()
		}
		more_work()
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: deeply nested if inside another if body should NOT suggest guard clause
// The inner if is complex but is nested inside another if's body
@(test)
diagnostic_invert_if_deeply_nested :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	if outer {
		// This inner if should NOT trigger because it's in an if body
		if inner {
			step1()
			step2()
			step3()
		}
	} else {
		// Adding else to outer prevents outer from triggering guard clause
		other_work()
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: negated condition in switch case SHOULD suggest inversion
@(test)
diagnostic_invert_if_in_switch_case :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	switch x {
	case 1:
		if {<}!condition{>} {
			work()
		} else {
			other()
		}
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "negation")
}

// Test: negated condition in inline proc literal SHOULD suggest inversion
@(test)
diagnostic_invert_if_in_inline_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	callback := proc() {
		if {<}!x{>} {
			handle()
		} else {
			process()
		}
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "negation")
}

// Test: empty if body should NOT suggest inversion (nothing to gain)
@(test)
diagnostic_invert_if_empty_body :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	if x > 0 {
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: if in defer statement with negated condition SHOULD suggest
@(test)
diagnostic_invert_if_in_defer :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	defer {
		if {<}!cleanup_needed{>} {
			skip()
		} else {
			cleanup()
		}
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "negation")
}

// Test: complexity exactly at threshold - 2 statements should NOT trigger
@(test)
diagnostic_invert_if_complexity_below_threshold :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	if x > 0 {
		step1()
		step2()
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}

// Test: complexity at threshold - 3 statements SHOULD trigger for guard clause
@(test)
diagnostic_invert_if_complexity_at_threshold :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	if {<}x > 0{>} {
		step1()
		step2()
		step3()
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "guard clause")
}

// Test: guard clause opportunity at end of loop (top-level in loop)
@(test)
diagnostic_invert_if_guard_clause_in_loop :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	for item in items {
		if {<}should_process(item){>} {
			step1(item)
			step2(item)
			step3(item)
		}
	}
}
`,
		extra_files = {},
		config = {enable_invert_if_diagnostics = true},
	}

	test.expect_diagnostic_at(t, &source, INVERT_IF_DIAGNOSTIC_CODE, "guard clause")
}