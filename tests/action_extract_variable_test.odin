package tests

import "core:testing"

import test "src:testing"

EXTRACT_VARIABLE_ACTION :: "Extract Variable"

@(test)
action_extract_variable_simple_binary_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
	y := 2
-	z := {<}x + y{>}
+	extracted := x + y
+	z := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_complex_arithmetic :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 10
	b := 20
-	c := {<}a + b * 2{>}
+	extracted := a + b * 2
+	c := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_call_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

helper :: proc(n: int) -> int { return n * 2 }

main :: proc() {
	x := 5
-	y := {<}helper(x){>}
+	extracted := helper(x)
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_call_with_binary :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

helper :: proc(n: int) -> int { return n * 2 }

main :: proc() {
	x := 5
-	y := {<}helper(x) + 10{>}
+	extracted := helper(x) + 10
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_nested_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

inner :: proc(n: int) -> int { return n + 1 }
outer :: proc(n: int) -> int { return n * 2 }

main :: proc() {
	x := 5
-	y := {<}outer(inner(x)){>}
+	extracted := outer(inner(x))
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_ternary_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	y := {<}x > 0 ? 1 : 0{>}
+	extracted := x > 0 ? 1 : 0
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_comparison_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	if {<}x > 0{>} {
+	extracted := x > 0
+	if extracted {
		y := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_logical_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y := 10
-	if {<}x > 0 && y < 20{>} {
+	extracted := x > 0 && y < 20
+	if extracted {
		z := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_selector_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Point :: struct { x, y: int }

main :: proc() {
	p := Point{1, 2}
-	z := {<}p.x + p.y{>}
+	extracted := p.x + p.y
+	z := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_index_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [3]int{1, 2, 3}
	i := 1
-	z := {<}arr[i] + arr[0]{>}
+	extracted := arr[i] + arr[0]
+	z := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_unary_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	y := {<}-x{>}
+	extracted := -x
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_paren_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
-	c := {<}(a + b) * 2{>}
+	extracted := (a + b) * 2
+	c := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_inner_paren_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
-	c := {<}(a + b){>} * 2
+	extracted := (a + b)
+	c := extracted * 2
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_type_cast :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	y := {<}f32(x){>}
+	extracted := f32(x)
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_compound_literal :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Point :: struct { x, y: int }

main :: proc() {
	a := 1
	b := 2
-	p := {<}Point{x = a, y = b}{>}
+	extracted := Point{x = a, y = b}
+	p := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_len_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [3]int{1, 2, 3}
-	n := {<}len(arr){>}
+	extracted := len(arr)
+	n := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_if_condition :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y := 10
-	if {<}x + y > 10{>} {
+	extracted := x + y > 10
+	if extracted {
		z := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_for_condition_not_available :: proc(t: ^testing.T) {
	// Cannot extract because `i` is only available inside the for loop
	source := test.Source {
		main     = `package test

main :: proc() {
	limit := 10
	for i := 0; {<}i < limit{>}; i += 1 {
	}
}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_in_for_condition_with_outer_vars :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	limit := 10
	max := 20
	for i := 0; i < 10; i += 1 {
-		if {<}limit < max{>} {
+		extracted := limit < max
+		if extracted {
			break
		}
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_switch_condition :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	switch {<}x + 1{>} {
+	extracted := x + 1
+	switch extracted {
	case 1:
	case 2:
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_return_stmt :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

compute :: proc(x: int) -> int {
-	return {<}x * 2 + 1{>}
+	extracted := x * 2 + 1
+	return extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_assignment_rhs :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y: int
-	y = {<}x * 2{>}
+	extracted := x * 2
+	y = extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_slice_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [5]int{1, 2, 3, 4, 5}
-	slice := {<}arr[1:3]{>}
+	extracted := arr[1:3]
+	slice := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_deref_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	ptr := &x
-	y := {<}ptr^ + 1{>}
+	extracted := ptr^ + 1
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_address_of_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	ptr := {<}&x{>}
+	extracted := &x
+	ptr := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_map_access :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	m := make(map[string]int)
-	val := {<}m["key"]{>}
+	extracted := m["key"]
+	val := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_or_else_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	m := make(map[string]int)
-	val := {<}m["key"] or_else 0{>}
+	extracted := m["key"] or_else 0
+	val := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_nested_selector :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Inner :: struct { value: int }
Outer :: struct { inner: Inner }

main :: proc() {
	o := Outer{inner = Inner{value = 5}}
-	x := {<}o.inner.value + 1{>}
+	extracted := o.inner.value + 1
+	x := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_not_equal :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	if {<}x != 0{>} {
+	extracted := x != 0
+	if extracted {
		y := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_nested_comparison :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
	c := 2
-	if {<}a < b && b == c{>} {
+	extracted := a < b && b == c
+	if extracted {
		x := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_nested_if :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	if x > 0 {
-		y := {<}x * 2{>}
+		extracted := x * 2
+		y := extracted
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_else_block :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	if x > 10 {
		y := 1
	} else {
-		y := {<}x + 5{>}
+		extracted := x + 5
+		y := extracted
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_for_loop_body :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	for i := 0; i < 10; i += 1 {
-		x := {<}i * 2{>}
+		extracted := i * 2
+		x := extracted
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_for_loop_body_outer_var :: proc(t: ^testing.T) {
	// Using outer variable inside loop body - extraction still goes inside body
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	multiplier := 3
	for i := 0; i < 10; i += 1 {
-		x := {<}multiplier * 2{>}
+		extracted := multiplier * 2
+		x := extracted
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_range_loop_body :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [3]int{1, 2, 3}
	for val in arr {
-		x := {<}val + 1{>}
+		extracted := val + 1
+		x := extracted
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_range_loop_body_outer_var :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	arr := [3]int{1, 2, 3}
	multiplier := 2
	for val in arr {
-		x := {<}multiplier * 10{>}
+		extracted := multiplier * 10
+		x := extracted
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_switch_case :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
	switch x {
	case 1:
-		y := {<}x * 10{>}
+		extracted := x * 10
+		y := extracted
	case 2:
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}


// Tests for when the action should NOT be available

@(test)
action_extract_variable_not_available_for_simple_ident :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	y := {<}x{>}
}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_not_available_for_after_taking_address :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5
	y := &{<}x{>}
}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_not_available_for_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := {<}42{>}
}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_not_available_when_selecting_entire_multi_assignment :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x, y := {<}42, 43{>}
}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_not_available_for_string_literal :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := {<}"hello"{>}
}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_not_available_for_empty_selection :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 5{*}
}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_not_available_outside_proc :: proc(t: ^testing.T) {
	source := test.Source {
		main     = `package test

{<}CONSTANT :: 42{>}

main :: proc() {}
`,
		extra_files = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_partial_expr_matched :: proc(t: ^testing.T) {
	// Selecting part of an expression that doesn't match exact node boundaries
	// should still allow extraction - user explicitly wants a semantic change
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	x := 1 + {<}2 + 3{>}
+	extracted := 2 + 3
+	x := 1 + extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_complex_nested_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 1
	b := 2
	c := 3
-	d := (a + b) * {<}(c - 1) / 2{>}
+	extracted := (c - 1) / 2
+	d := (a + b) * extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_array_literal :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
	y := 2
-	arr := {<}[3]int{x, y, 3}{>}
+	extracted := [3]int{x, y, 3}
+	arr := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_inside_array_literal :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
	y := 2
-	arr := [3]int{x, y, {<}3 + 5{>}}
+	extracted := 3 + 5
+	arr := [3]int{x, y, extracted}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_deeply_nested_scope :: proc(t: ^testing.T) {
	// Extraction IS valid - the extracted variable goes INSIDE the innermost body
	// where both `i` and `j` are still in scope
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	for i := 0; i < 10; i += 1 {
		if i > 5 {
			for j := 0; j < 5; j += 1 {
-				x := {<}i * j{>}
+				extracted := i * j
+				x := extracted
			}
		}
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_deeply_nested_scope_outer_var :: proc(t: ^testing.T) {
	// Also valid - using outer variables inside nested loop body
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 3
	b := 4
	for i := 0; i < 10; i += 1 {
		if i > 5 {
			for j := 0; j < 5; j += 1 {
-				x := {<}a * b{>}
+				extracted := a * b
+				x := extracted
			}
		}
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_expr_stmt :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

do_something :: proc(n: int) {}

main :: proc() {
	x := 5
-	do_something({<}x + 1{>})
+	extracted := x + 1
+	do_something(extracted)
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_auto_cast :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x: f32 = 5
-	y: i32 = {<}auto_cast x{>}
+	extracted: i32 = auto_cast x
+	y: i32 = extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_auto_cast_infer_type :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x: f32 = 5
	y: i32 = 10
-	y = {<}auto_cast x{>}
+	extracted: i32 = auto_cast x
+	y = extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_in_nested_block :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	{
-		y := {<}x * 2{>}
+		extracted := x * 2
+		y := extracted
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_dynamic_array_make :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	size := 10
-	arr := {<}make([dynamic]int, size){>}
+	extracted := make([dynamic]int, size)
+	arr := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_complex_condition :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 5
	b := 10
	c := 15
-	if {<}(a > 0 && b < 20) || c == 15{>} {
+	extracted := (a > 0 && b < 20) || c == 15
+	if extracted {
		x := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_part_of_complex_condition :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 5
	b := 10
	c := 15
-	if {<}(a > 0 && b < 20){>} || c == 15 {
+	extracted := (a > 0 && b < 20)
+	if extracted || c == 15 {
		x := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_multi_assign_first :: proc(t: ^testing.T) {
	// Extract the first expression in a multiple value declaration
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y := 10
-	a, b := {<}x + 1{>}, y + 2
+	extracted := x + 1
+	a, b := extracted, y + 2
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_multi_assign_second :: proc(t: ^testing.T) {
	// Extract the second expression in a multiple value declaration
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y := 10
-	a, b := x + 1, {<}y + 2{>}
+	extracted := y + 2
+	a, b := x + 1, extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_multi_assign_stmt_first :: proc(t: ^testing.T) {
	// Extract the first expression in a multiple assignment statement
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y := 10
	a := 0
	b := 0
-	a, b = {<}x * 2{>}, y * 3
+	extracted := x * 2
+	a, b = extracted, y * 3
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_multi_assign_stmt_second :: proc(t: ^testing.T) {
	// Extract the second expression in a multiple assignment statement
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
	y := 10
	a := 0
	b := 0
-	a, b = x * 2, {<}y * 3{>}
+	extracted := y * 3
+	a, b = x * 2, extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_multi_assign_auto_cast :: proc(t: ^testing.T) {
	// Extract auto_cast in a multiple assignment - should infer type from LHS
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x: f32 = 5
	y := 10
	a: i32 = 0
	b := 0
-	a, b = {<}auto_cast x{>}, y
+	extracted: i32 = auto_cast x
+	a, b = extracted, y
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_multi_value_decl_auto_cast :: proc(t: ^testing.T) {
	// Extract auto_cast in a multiple value declaration with type annotation
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x: f32 = 5
	y := 10
-	a, b: i32 = {<}auto_cast x{>}, y
+	extracted: i32 = auto_cast x
+	a, b: i32 = extracted, y
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_triple_assign :: proc(t: ^testing.T) {
	// Extract middle expression in a triple value declaration
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
	y := 2
	z := 3
-	a, b, c := x, {<}y * 10{>}, z
+	extracted := y * 10
+	a, b, c := x, extracted, z
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}
