package tests

import "core:testing"

import test "src:testing"

INLINE_ALIAS_ACTION :: "Inline Alias"

// ============================================================================
// Basic inlining tests
// ============================================================================

@(test)
action_inline_alias_simple_on_usage :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

MyAlias :: int

main :: proc() {
-	x: MyA{*}lias
+	x: int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_on_definition_removes_declaration :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MyAlias {*}:: int

main :: proc() {
-	x: MyAlias
+	x: int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_multiple_usages :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MyAlias {*}:: int

main :: proc() {
-	x: MyAlias
-	y: MyAlias
-	z: MyAlias
+	x: int
+	y: int
+	z: int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_pointer_type :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-PtrAlias {*}:: ^int

main :: proc() {
-	x: PtrAlias
+	x: ^int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_array_type :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-ArrAlias {*}:: [10]int

main :: proc() {
-	x: ArrAlias
+	x: [10]int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_dynamic_array :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-DynAlias {*}:: [dynamic]int

main :: proc() {
-	x: DynAlias
+	x: [dynamic]int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_slice :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-SliceAlias {*}:: []int

main :: proc() {
-	x: SliceAlias
+	x: []int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_map_type :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MapAlias {*}:: map[string]int

main :: proc() {
-	x: MapAlias
+	x: map[string]int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

// ============================================================================
// Cross-package alias tests (requires imports)
// ============================================================================

@(test)
action_inline_alias_cross_package_simple :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

import "core:mem"

-MyAre{*}na :: mem.Arena
`},
			{
				pkg = "another",
				source = `package another

-import "test"
+import "core:mem"

-sample_usage :: proc(m: test.MyArena) {}
+sample_usage :: proc(m: mem.Arena) {}
`,
			},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_cross_package_multiple_usages :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

import "core:mem"

-MyArena {*}:: mem.Arena
`},
			{
				pkg = "test",
				filename = "file2",
				source = `package test

+import "core:mem"
+
-proc1 :: proc(m: MyArena) {}
-proc2 :: proc(m: MyArena) {}
+proc1 :: proc(m: mem.Arena) {}
+proc2 :: proc(m: mem.Arena) {}
`,
			},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_existing_import_same_alias :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

import "core:mem"

-MyArena {*}:: mem.Arena
`},
			{
				pkg = "test",
				filename = "file2",
				source = `package test

import "core:mem"

-sample_usage :: proc(m: MyArena) {}
+sample_usage :: proc(m: mem.Arena) {}
`,
			},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_existing_import_different_alias :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

import "core:mem"

-MyArena {*}:: mem.Arena
`},
			{
				pkg = "test",
				filename = "file2",
				source = `package test

import something "core:mem"

-sample_usage :: proc(m: MyArena) {}
+sample_usage :: proc(m: something.Arena) {}
`,
			},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_builtin_type :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-Number {*}:: int

main :: proc() {
-	x: Number
+	x: int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

// ============================================================================
// Nested alias tests (one layer of inlining)
// ============================================================================

@(test)
action_inline_alias_nested_one_layer :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

B :: int
-A {*}:: B

main :: proc() {
-	x: A
+	x: B
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_nested_two_layers :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

C :: int
B :: C
-A {*}:: B

main :: proc() {
-	x: A
+	x: B
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_nested_cross_package :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

import "core:mem"

B :: mem.Arena
-A {*}:: B
`},
			{
				pkg = "test",
				filename = "file2",
				source = `package test

-sample_usage :: proc(m: A) {}
+sample_usage :: proc(m: B) {}
`,
			},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

// ============================================================================
// Edge cases and restrictions
// ============================================================================

@(test)
action_inline_alias_distinct_should_not_be_available :: proc(t: ^testing.T) {
	// This test expects the action NOT to be available
	test.expect_no_action(
		t,
		`package test

MyInt {*}:: distinct int

main :: proc() {
	x: MyInt
}
`,
		INLINE_ALIAS_ACTION,
	)
}

@(test)
action_inline_alias_proc_alias :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MyProc {*}:: proc(int) -> int

main :: proc() {
-	f: MyProc
+	f: proc(int) -> int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_struct_field :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MyInt {*}:: int

MyStruct :: struct {
-	field: MyInt,
+	field: int,
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_in_proc_signature :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MyInt {*}:: int

-my_proc :: proc(x: MyInt) -> MyInt {
+my_proc :: proc(x: int) -> int {
	return x
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_single_usage_only :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

MyAlias :: int

main :: proc() {
-	x: MyAli{*}as
+	x: int
	y: MyAlias
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_preserves_comments :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MyAlias {*}:: int

main :: proc() {
	// This is a comment
-	x: MyAlias
+	x: int
}
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}

@(test)
action_inline_alias_multiline_type :: proc(t: ^testing.T) {
	src := test.Source {
		files = {
			{source = `package test

-MyProc {*}:: proc(
-	x: int,
-	y: int,
-) -> int

-my_proc: MyProc
+my_proc: proc(
+	x: int,
+	y: int,
+) -> int
`},
		},
	}
	test.expect_code_action_diff(t, INLINE_ALIAS_ACTION, &src)
}