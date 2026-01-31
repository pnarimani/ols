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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
		config = {enable_invert_if_diagnostics = false},
	}

	test.expect_no_diagnostic(t, &source, INVERT_IF_DIAGNOSTIC_CODE)
}
