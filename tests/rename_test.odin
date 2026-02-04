package tests

import "core:fmt"
import "core:testing"

import "src:common"

import test "src:testing"

@(test)
ast_prepare_rename_enum_field_list :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: enum {
			a = 1,
		}

		main :: proc() {
			foo: Foo
			foo = .a{*}
		}
		`}},
	}
	range := common.Range{start = {line = 8, character = 10}, end = {line = 8, character = 11}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_enum_field_list_with_constant :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		one :: 1

		Foo :: enum {
			a = on{*}e,
		}
		`}},
	}

	range := common.Range{start = {line = 5, character = 7}, end = {line = 5, character = 10}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := Foo{
				b{*}ar = 1,
			}
		}
		`}},
	}

	range := common.Range{start = {line = 8, character = 4}, end = {line = 8, character = 7}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_selector :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := Foo{}
			foo.ba{*}r = 1
		}
		`}},
	}

	range := common.Range{start = {line = 8, character = 7}, end = {line = 8, character = 10}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: struct {
			bar: int,
		}

		main :: proc() {
			foo := Fo{*}o{}
		}
		`}},
	}

	range := common.Range{start = {line = 7, character = 10}, end = {line = 7, character = 13}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_type :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Bar :: struct {}

		Foo :: struct {
			bar: B{*}ar,
		}
		`}},
	}

	range := common.Range{start = {line = 5, character = 8}, end = {line = 5, character = 11}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_type_package :: proc (t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "my_package",
			source = `package my_package
		My_Struct :: struct {}
		`,
		},
	)
	inject_at(&packages, 0, test.FileInPackage{source = `package test
		import "my_package"

		Foo :: struct {
			bar: my_package.My_Stru{*}ct,
		}
		`})
source := test.Source {
	files = packages[:],
	}

	range := common.Range{start = {line = 4, character = 19}, end = {line = 4, character = 28}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_union_type :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: struct {
			bar: int,
		}
		
		Bar :: struct {}

		Foo_Bar :: union {
			Fo{*}o,
			Bar,
		}
		`}},
	}

	range := common.Range{start = {line = 9, character = 3}, end = {line = 9, character = 6}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_symbol_behind_for :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		
		main :: proc() {
			foos := [5]int{1,2,3,4,5}
			for f{*}oo in foos {
			}
		}
		`}},
	}

	range := common.Range{start = {line = 4, character = 7}, end = {line = 4, character = 10}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_symbol_behind_for_with_label :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		
		main :: proc() {
			foos := [5]int{1,2,3,4,5}
			my_for: for f{*}oo in foos {
			}
		}
		`}},
	}

	range := common.Range{start = {line = 4, character = 15}, end = {line = 4, character = 18}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_enumerated_array :: proc (t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: enum {
			A,
			B,
		}

		main :: proc() {
			foos := [Foo]Foo {
				.A{*} = .B,
			}
		}
		`}},
	}

	range := common.Range{start = {line = 9, character = 5}, end = {line = 9, character = 6}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_ptr :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: struct {
			bar: ^Ba{*}r
		}

		Bar :: struct {}
		`}},
	}

	range := common.Range{start = {line = 3, character = 9}, end = {line = 3, character = 12}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_enumerated_array :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foos: [F{*}oo]int
		}
		`}},
	}

	range := common.Range{start = {line = 8, character = 10}, end = {line = 8, character = 13}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_map :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foos: map[F{*}oo]int
		}
		`}},
	}

	range := common.Range{start = {line = 8, character = 13}, end = {line = 8, character = 16}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_dynamic_array :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foos: [dynamic]Fo{*}o
		}
		`}},
	}

	range := common.Range{start = {line = 8, character = 18}, end = {line = 8, character = 21}}
	test.expect_prepare_rename_range(t, &source, range)
}

@(test)
ast_prepare_rename_struct_field_bit_set :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: enum {
			A,
			B,
		}

		Bar :: struct {
			foos: bit_set[Fo{*}o]
		}
		`}},
	}

	range := common.Range{start = {line = 8, character = 17}, end = {line = 8, character = 20}}
	test.expect_prepare_rename_range(t, &source, range)
}

// get_rename tests using diff format

@(test)
rename_local_variable :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
-	fo{*}o := 42
+	bar := 42
-	x := foo + 1
+	x := bar + 1
}
`}},
	}

	test.expect_rename_diff(t, "bar", &source)
}

@(test)
rename_function_parameter :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

-my_func :: proc(va{*}l: int) -> int {
+my_func :: proc(new_val: int) -> int {
-	return val * 2
+	return new_val * 2
}
`}},
	}

	test.expect_rename_diff(t, "new_val", &source)
}

@(test)
rename_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

Foo :: struct {
-	ba{*}r: int,
+	baz: int,
}

main :: proc() {
	f := Foo{}
-	f.bar = 10
+	f.baz = 10
}
`}},
	}

	test.expect_rename_diff(t, "baz", &source)
}

@(test)
rename_struct_type :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

-Fo{*}o :: struct {
+Bar :: struct {
	x: int,
}

main :: proc() {
-	f := Foo{}
+	f := Bar{}
}
`}},
	}

	test.expect_rename_diff(t, "Bar", &source)
}

@(test)
rename_enum_field :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

Color :: enum {
-	Re{*}d,
+	Crimson,
	Green,
	Blue,
}

main :: proc() {
-	c := Color.Red
+	c := Color.Crimson
}
`}},
	}

	test.expect_rename_diff(t, "Crimson", &source)
}

@(test)
rename_procedure :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

-hel{*}per :: proc() -> int {
+utility :: proc() -> int {
	return 42
}

main :: proc() {
-	x := helper()
+	x := utility()
}
`}},
	}

	test.expect_rename_diff(t, "utility", &source)
}

@(test)
rename_variable_multiple_usages :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
-	coun{*}t := 0
+	total := 0
-	count += 1
+	total += 1
-	count += 2
+	total += 2
-	result := count * 2
+	result := total * 2
}
`}},
	}

	test.expect_rename_diff(t, "total", &source)
}

@(test)
rename_for_loop_variable :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

main :: proc() {
	arr := [5]int{1, 2, 3, 4, 5}
-	for va{*}l in arr {
+	for item in arr {
-		x := val * 2
+		x := item * 2
	}
}
`}},
	}

	test.expect_rename_diff(t, "item", &source)
}

@(test)
rename_implicit_enum_selector :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

Color :: enum {
-	Re{*}d,
+	Crimson,
	Green,
	Blue,
}

main :: proc() {
	c: Color
-	c = .Red
+	c = .Crimson
}
`}},
	}

	test.expect_rename_diff(t, "Crimson", &source)
}

@(test)
rename_nested_struct_field :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

Inner :: struct {
-	va{*}l: int,
+	value: int,
}

Outer :: struct {
	inner: Inner,
}

main :: proc() {
	o := Outer{}
-	o.inner.val = 10
+	o.inner.value = 10
}
`}},
	}

	test.expect_rename_diff(t, "value", &source)
}

@(test)
rename_multiple_parameters :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

-compute :: proc(va{*}l: int, multiplier: int) -> int {
+compute :: proc(input: int, multiplier: int) -> int {
-	return val * multiplier
+	return input * multiplier
}
`}},
	}

	test.expect_rename_diff(t, "input", &source)
}

@(test)
rename_constant :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

-MAX_VA{*}LUE :: 100
+MAX_SIZE :: 100

main :: proc() {
-	arr: [MAX_VALUE]int
+	arr: [MAX_SIZE]int
}
`}},
	}

	test.expect_rename_diff(t, "MAX_SIZE", &source)
}

@(test)
rename_union_variant_type :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

-Fo{*}o :: struct {
+Bar :: struct {
	x: int,
}

Baz :: struct {}

-FooOrBaz :: union { Foo, Baz }
+FooOrBaz :: union { Bar, Baz }

main :: proc() {
-	v: FooOrBaz = Foo{}
+	v: FooOrBaz = Bar{}
}
`}},
	}

	test.expect_rename_diff(t, "Bar", &source)
}

// Cross-file rename tests (same package)

@(test)
rename_cross_file_struct :: proc(t: ^testing.T) {
	source := test.Source {
		files = {
			{
				filename = "types",
				source = `package test

-Fo{*}o :: struct {
+Bar :: struct {
	x: int,
}
`,
			},
			{
				filename = "main",
				source = `package test

main :: proc() {
-	f := Foo{}
+	f := Bar{}
	f.x = 10
}
`,
			},
		},
	}

	test.expect_rename_diff(t, "Bar", &source)
}

@(test)
rename_cross_file_procedure :: proc(t: ^testing.T) {
	source := test.Source {
		files = {
			{
				filename = "helpers",
				source = `package test

-hel{*}per :: proc() -> int {
+utility :: proc() -> int {
	return 42
}
`,
			},
			{
				filename = "main",
				source = `package test

main :: proc() {
-	x := helper()
+	x := utility()
-	y := helper() + 1
+	y := utility() + 1
}
`,
			},
		},
	}

	test.expect_rename_diff(t, "utility", &source)
}

@(test)
rename_cross_file_enum_field :: proc(t: ^testing.T) {
	source := test.Source {
		files = {
			{
				filename = "types",
				source = `package test

Color :: enum {
-	Re{*}d,
+	Crimson,
	Green,
	Blue,
}
`,
			},
			{
				filename = "main",
				source = `package test

main :: proc() {
-	c := Color.Red
+	c := Color.Crimson
-	if c == .Red {
+	if c == .Crimson {
	}
}
`,
			},
		},
	}

	test.expect_rename_diff(t, "Crimson", &source)
}

@(test)
rename_struct_field_cross_file :: proc(t: ^testing.T) {
	source := test.Source {
		files = {
			{
				filename = "types",
				source = `package test

Person :: struct {
-	na{*}me: string,
+	full_name: string,
	age: int,
}
`,
			},
			{
				filename = "main",
				source = `package test

main :: proc() {
	p := Person{}
-	p.name = "Alice"
+	p.full_name = "Alice"
}
`,
			},
		},
	}

	test.expect_rename_diff(t, "full_name", &source)
}

@(test)
rename_multiple_files_same_package :: proc(t: ^testing.T) {
	source := test.Source {
		files = {
			{
				filename = "types",
				source = `package test

-Perso{*}n :: struct {
+User :: struct {
	name: string,
	age: int,
}
`,
			},
			{
				filename = "utils",
				source = `package test

-create_person :: proc() -> Person {
+create_person :: proc() -> User {
-	return Person{name = "Alice", age = 30}
+	return User{name = "Alice", age = 30}
}
`,
			},
			{
				filename = "main",
				source = `package test

main :: proc() {
-	p: Person
+	p: User
	p = create_person()
}
`,
			},
		},
	}

	test.expect_rename_diff(t, "User", &source)
}

// Cross-package rename tests

@(test)
rename_cross_package_struct :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "my_package",
			source = `package my_package

-My_Stru{*}ct :: struct {
+Renamed_Struct :: struct {
	value: int,
}
`,
		},
	)

	inject_at(
		&packages,
		0,
		test.FileInPackage {
			source = `package test

import "my_package"

main :: proc() {
-	s := my_package.My_Struct{}
+	s := my_package.Renamed_Struct{}
	s.value = 42
}
`,
		},
	)

	source := test.Source {
		files = packages[:],
	}

	test.expect_rename_diff(t, "Renamed_Struct", &source)
}

@(test)
rename_cross_package_procedure :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "utils",
			source = `package utils

-hel{*}per :: proc() -> int {
+utility :: proc() -> int {
	return 42
}
`,
		},
	)

	inject_at(
		&packages,
		0,
		test.FileInPackage {
			source = `package test

import "utils"

main :: proc() {
-	x := utils.helper()
+	x := utils.utility()
}
`,
		},
	)

	source := test.Source {
		files = packages[:],
	}

	test.expect_rename_diff(t, "utility", &source)
}

@(test)
rename_cross_package_enum_field :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "types",
			source = `package types

Color :: enum {
-	Re{*}d,
+	Crimson,
	Green,
	Blue,
}
`,
		},
	)

	inject_at(
		&packages,
		0,
		test.FileInPackage {
			source = `package test

import "types"

main :: proc() {
-	c := types.Color.Red
+	c := types.Color.Crimson
}
`,
		},
	)

	source := test.Source {
		files = packages[:],
	}

	test.expect_rename_diff(t, "Crimson", &source)
}