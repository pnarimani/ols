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
action_extract_variable_min_max :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 5
	b := 10
-	c := {<}min(a, b){>}
+	extracted := min(a, b)
+	c := extracted
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
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_in_for_condition_with_outer_vars :: proc(t: ^testing.T) {
	// This is valid because both limit and max are defined outside the loop
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
action_extract_variable_greater_equal :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	age := 25
-	if {<}age >= 21{>} {
+	extracted := age >= 21
+	if extracted {
		x := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_less_equal :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	score := 45
-	if {<}score <= 50{>} {
+	extracted := score <= 50
+	if extracted {
		x := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_pointer_comparison :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Data :: struct { value: int }

main :: proc() {
	ptr: ^Data = nil
-	if {<}ptr != nil{>} {
+	extracted := ptr != nil
+	if extracted {
		x := ptr.value
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
	// CRITICAL: The extracted variable MUST go INSIDE the loop body
	// where the loop variable `i` is in scope
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
	// CRITICAL: The extracted variable MUST go INSIDE the loop body
	// where the loop variable `val` is in scope
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
	// Using outer variable inside loop body
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

@(test)
action_extract_variable_bitwise_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 0xFF
	b := 0x0F
-	c := {<}a & b{>}
+	extracted := a & b
+	c := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_shift_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 1
-	y := {<}x << 4{>}
+	extracted := x << 4
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_string_concat :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

import "core:strings"

main :: proc() {
	a := "Hello"
	b := "World"
-	c := {<}strings.concatenate({a, b}){>}
+	extracted := strings.concatenate({a, b})
+	c := extracted
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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
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
		packages = {},
	}

	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_partial_expr_not_matched :: proc(t: ^testing.T) {
	// Selecting part of an expression that doesn't match node boundaries
	// should not trigger the action
	source := test.Source {
		main     = `package test

main :: proc() {
	x := 1 + {<}2 + 3{>}
}
`,
		packages = {},
	}

	// "2 + 3" doesn't match a complete AST node since "1 + 2 + 3" parses
	// left-associatively as "(1 + 2) + 3", not "1 + (2 + 3)"
	test.expect_action_excludes(t, &source, {EXTRACT_VARIABLE_ACTION})
}

@(test)
action_extract_variable_with_proc_param :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

process :: proc(n: int) {
-	result := {<}n * 2{>}
+	extracted := n * 2
+	result := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_multiple_args_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

add :: proc(a, b: int) -> int { return a + b }

main :: proc() {
	x := 5
	y := 10
-	z := {<}add(x, y){>}
+	extracted := add(x, y)
+	z := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_builtin_size_of :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	n := {<}size_of(int){>}
+	extracted := size_of(int)
+	n := extracted
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
-	d := {<}(a + b) * (c - 1) / 2{>}
+	extracted := (a + b) * (c - 1) / 2
+	d := extracted
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
action_extract_variable_with_float_arithmetic :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x: f32 = 3.14
	y: f32 = 2.0
-	z := {<}x * y{>}
+	extracted := x * y
+	z := extracted
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
action_extract_variable_negative_number :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	y := {<}x + -10{>}
+	extracted := x + -10
+	y := extracted
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
action_extract_variable_modulo_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 17
-	y := {<}x % 5{>}
+	extracted := x % 5
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_not_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	flag := true
-	if {<}!flag{>} {
+	extracted := !flag
+	if extracted {
		x := 1
	}
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_xor_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 0xFF
-	b := {<}~a{>}
+	extracted := ~a
+	b := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_or_expr :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	a := 0xF0
	b := 0x0F
-	c := {<}a | b{>}
+	extracted := a | b
+	c := extracted
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
	x: i32 = 5
-	y: i64 = {<}auto_cast x{>}
+	extracted := auto_cast x
+	y: i64 = extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_transmute :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x: i32 = 5
-	y := {<}transmute(u32)x{>}
+	extracted := transmute(u32)x
+	y := extracted
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
action_extract_variable_method_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

import "core:strings"

main :: proc() {
	s := "hello world"
-	parts := {<}strings.split(s, " "){>}
+	extracted := strings.split(s, " ")
+	parts := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_abs_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := -5
-	y := {<}abs(x){>}
+	extracted := abs(x)
+	y := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_clamp_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 15
-	y := {<}clamp(x, 0, 10){>}
+	extracted := clamp(x, 0, 10)
+	y := extracted
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
action_extract_variable_map_make :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	m := {<}make(map[string]int){>}
+	extracted := make(map[string]int)
+	m := extracted
}
`,
		EXTRACT_VARIABLE_ACTION,
	)
}

@(test)
action_extract_variable_new_call :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

Data :: struct { value: int }

main :: proc() {
-	ptr := {<}new(Data){>}
+	extracted := new(Data)
+	ptr := extracted
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
