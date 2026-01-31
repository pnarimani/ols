package tests

import "core:testing"

import test "src:testing"

INVERT_IF_ACTION :: "Invert if"

@(test)
action_invert_if_simple :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	if x{*} >= 0 {
-		foo()
-	}
+	if x < 0 {
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_with_else :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := 5
-	if x{*} == 0 {
-		foo()
-	} else {
-		bar()
-	}
+	if x != 0 {
+		bar()
+	} else {
+		foo()
+	}
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_with_init :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if x{*} := foo(); x < 0 {
-		bar()
-	}
+	if x := foo(); x >= 0 {
+		return
+	}
+	bar()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_not_on_if :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x :={*} 5
}
`,
		packages = {},
	}

	// Should not have the invert action when not on an if statement
	test.expect_action(t, &source, {})
}


@(test)
action_invert_if_inside_of_statement :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	if x != 0 {
		foo{*}()
	}
}
`,
		packages = {},
	}

	test.expect_action(t, &source, {})
}

@(test)
action_invert_if_not_eq :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if x{*} != 0 {
-		foo()
-	}
+	if x == 0 {
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_lt :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if x{*} < 5 {
-		foo()
-	}
+	if x >= 5 {
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_gt :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if x{*} > 5 {
-		foo()
-	}
+	if x <= 5 {
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_le :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if x{*} <= 5 {
-		foo()
-	}
+	if x > 5 {
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_negated :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if !x{*} {
-		foo()
-	}
+	if x {
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_boolean :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if x{*} {
-		foo()
-	}
+	if !x {
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_else_if_chain :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := something()
-	if x{*} > 0 {
-		statement1()
-	} else if x < 0 {
-		statement2()
-	} else {
-		statement3()
-	}
+	if x <= 0 {
+		if x < 0 {
+			statement2()
+		} else {
+			statement3()
+		}
+	} else {
+		statement1()
+	}
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_not_on_else_if :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := something()
	if x > 0 {
		statement1()
	} else if x{*} < 0 {
		statement2()
	}
	statement3()
}
`,
		packages = {},
	}

	// Should not have the invert action when on an else-if statement
	test.expect_action_excludes(t, &source, {INVERT_IF_ACTION})
}

@(test)
action_invert_if_not_on_else :: proc(t: ^testing.T) {
	source := test.Source {
		main = `package test

main :: proc() {
	x := something()
	if x > 0 {
		statement1()
	} else {
		statement3(){*}
	}
}
`,
		packages = {},
	}

	// Should not have the invert action when in the else block (not on an if)
	test.expect_action(t, &source, {})
}

@(test)
action_invert_if_nested_in_else_if_body :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := something()
	if x > 0 {
		statement1()
	} else if x < 0 {
-		if y{*} > 0 {
-			statement2()
-		}
+		if y <= 0 {
+			return
+		}
+		statement2()
	} else {
		statement3()
	}
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_nested_in_else_if_body_with_trailing_stmt :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	x := something()
	if x > 0 {
		statement1()
	} else if x < 0 {
-		if y{*} > 0 {
-			statement2()
-		}
+		if y <= 0 {
+		} else {
+			statement2()
+		}
	}
	statement3()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_with_else_and_return_in_body :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
-	if x{*} == 0 {
-		foo()
-		return
-	}
-	bar()
+	if x != 0 {
+		bar()
+		return
+	}
+	foo()
}
`,
		INVERT_IF_ACTION,
	)
}

@(test)
action_invert_if_in_loop_with_continue :: proc(t: ^testing.T) {
	test.expect_code_action_diff(
		t,
		`package test

main :: proc() {
	for i in 0..<10 {
-		if x{*} < 0 {
-			foo()
-		}
+		if x >= 0 {
+			continue
+		}
+		foo()
	}
}
`,
		INVERT_IF_ACTION,
	)
}
