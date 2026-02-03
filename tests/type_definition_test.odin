package tests

import "core:testing"

import "src:common"

import test "src:testing"

@(test)
ast_type_definition_struct_definition :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Bar{:} :: struct {
			bar: int,
		}

		main :: proc() {
			b{*}ar := Bar{}
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_field_definition :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}
		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{
				ba{*}r = Foo{},
			}
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_field_definition_from_use :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}
			bar.ba{*}r = Foo{}
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		Foo :: struct {
			foo: string,
		}

		{:}Bar{:} :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}

			foo := b{*}ar.bar
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_field_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}

			foo := bar.b{*}ar
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_field_pointer_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: ^Foo,
		}

		main :: proc() {
			bar := Bar{}

			foo := bar.b{*}ar
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_local_pointer_from_rhs_use :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		Foo :: struct {
			foo: string,
		}

		{:}Bar{:} :: struct {
			bar: ^Foo,
		}

		main :: proc() {
			bar := &Bar{}

			foo := b{*}ar.bar
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_variable :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		Foo :: struct {
			foo: string,
		}

		{:}Bar{:} :: struct {
			bar: Foo,
		}

		main :: proc() {
			bar := Bar{}
			ba{*}r.bar = "Test"
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_field_definition_from_declaration :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		Bar :: struct {
			f{*}oo: Foo,
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_procedure_return_value :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		bar :: proc() -> Foo {
			return Foo{}
		}

		main :: proc() {
			f{*}oo := bar()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_procedure_mulitple_return_first_value :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		Bar :: struct {
			bar: int,
		}

		new_foo_bar :: proc() -> (Foo, Bar) {
			return Foo{}, Bar{}
		}

		main :: proc() {
			fo{*}o, bar := new_foo_bar()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_procedure_mulitple_return_second_value :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		Foo :: struct {
			foo: string,
		}

		{:}Bar{:} :: struct {
			bar: int,
		}

		new_foo_bar :: proc() -> (Foo, Bar) {
			return Foo{}, Bar{}
		}

		main :: proc() {
			foo, ba{*}r := new_foo_bar()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_builtin_type :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		main :: proc() {
			f{*}oo := "Hello, World!"
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_field_builtin_type :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		Foo :: struct {
			foo: string,
		}

		main :: proc() {
			foo := Foo{
				f{*}oo = "Hello, World!"
			}
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_struct_field_definition_from_declaration_builtin_type :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		Foo :: struct {
			f{*}oo: string,
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_on_proc_with_multiple_return_goto_first_return :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		foo :: proc() -> (Foo, bool) {
			return Foo{}, true
		}

		main :: proc() {
			my_foo, ok := f{*}oo()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_proc_first_return :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		foo :: proc() -> (Foo, bool) {
			return Foo{}, true
		}

		main :: proc() {
			my_foo, ok := f{*}oo()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_proc_with_no_return :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		foo :: proc() {
		}

		main :: proc() {
			f{*}oo()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_variable_array_type :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		Foo :: struct {
			my_int: int,
		}

		{:}Bar{:} :: struct {
			foo: Foo,
		}

		main :: proc() {
			bars: [2]Bar

			b{*}ars[0].foo = Foo{}
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_proc_from_definition :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		fo{*}o :: proc() -> (Foo, bool) {
			return Foo{}, true
		}

		main :: proc() {
			my_foo, ok := foo()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_proc_with_slice_return :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		fo{*}o :: proc() -> ([]Foo, bool) {
			return {}, true
		}

		main :: proc() {
			my_foo, ok := foo()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_param_of_proc :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: struct {
			foo: string,
		}

		do_foo :: proc(f: Foo) {
		}

		main :: proc() {
			foo := Foo{}
			do_foo(f{*}oo)
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_enum :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: enum {
			Foo1,
			Foo2,
		}

		get_foo :: proc() -> Foo {
			return .Foo1
		}

		main :: proc() {
			f{*}oo := get_foo()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_predeclared_variable :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Foo{:} :: union {
			i64,
			f64,
		}

		get_foo :: proc() -> Foo {
			return 0
		}

		main :: proc() {
			foo: Foo

			f{*}oo = get_foo()
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_external_package :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "my_package",
			source = `package my_package
		{:}My_Struct{:} :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
		},
	)
	inject_at(&packages, 0, test.FileInPackage{source = `package test
		import "my_package"

		main :: proc() {
			cool: my_package.My_Struct
			cool{*}
		}
		`})
source := test.Source {
	files = packages[:],
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_external_package_from_proc :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "my_package",
			source = `package my_package
		{:}My_Struct{:} :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
		},
	)
	inject_at(&packages, 0, test.FileInPackage{source = `package test
		import "my_package"

		get_my_struct :: proc() -> my_package.My_Struct {
			return my_package.My_Struct{}
		}

		main :: proc() {
			my_struct := ge{*}t_my_struct()
		}
		`})
source := test.Source {
	files = packages[:],
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_external_package_from_proc_slice_return :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "my_package",
			source = `package my_package
		{:}My_Struct{:} :: struct {
			one: int,
			two: int,
			three: int,
		}
		`,
		},
	)
	inject_at(&packages, 0, test.FileInPackage{source = `package test
		import "my_package"

		get_my_struct :: proc() -> []my_package.My_Struct {
			return {}
		}

		main :: proc() {
			my_struct := ge{*}t_my_struct()
		}
		`})
source := test.Source {
	files = packages[:],
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_external_package_from_external_proc :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "my_package",
			source = `package my_package
		{:}My_Struct{:} :: struct {
			one: int,
			two: int,
			three: int,
		}

		get_my_struct :: proc() -> My_Struct {
			return My_Struct{}
		}
		`,
		},
	)
	inject_at(&packages, 0, test.FileInPackage{source = `package test
		import "my_package"

		main :: proc() {
			my_struct := my_package.ge{*}t_my_struct()
		}
		`})
source := test.Source {
	files = packages[:],
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_array_of_pointers :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		{:}Foo{:} :: struct {
			bar: int,
		}

		main :: proc() {
			foos := []^Foo{}
			l := len(f{*}oos)
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_type_cast :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		{:}Foo{:} :: struct {
			bar: int,
		}

		main :: proc() {
			data: ^int
			foo := cast(^Foo)data

			bar := fo{*}o.bar
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_proc_named_param :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		{:}Bar{:} :: struct{
			bar: int,
		}

		foo :: proc(a: Bar) {}

		main :: proc() {
			a := "hellope"
			foo(a{*} = {})
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_proc_named_param_with_default_value :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		{:}Bar{:} :: struct{
			bar: int,
		}

		bar := Bar{}

		foo :: proc(a := bar) {}

		main :: proc() {
			b := Bar{}
			foo(a{*} = b)
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_multi_pointer :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		Foo :: struct {
			b{*}ars: [^]Bar,
		}

		{:}Bar{:} :: struct{
			bar: int,
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_comp_lit_proc_arg :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		{:}Foo{:} :: struct{}

		bar :: proc(foo: Foo) {}

		main :: proc() {
			bar({{*}})
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_comp_lit_variable :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		{:}Foo{:} :: struct{}

		main :: proc() {
			foo: Foo = {{*}}
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_variable_in_comp_lit :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test

		{:}Foo{:} :: struct{}

		Bar :: struct {
			foo: Foo,
		}

		main :: proc() {
			foo := Foo{}
			bar := Bar {
				foo = fo{*}o,
			}
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_polymorphic_type_with_specialization :: proc(t: ^testing.T) {
	source := test.Source {
		files = {{source = `package test
		{:}Vec{:} :: [2]f32
		foo :: proc (a: $T/[$N]$E) -> T {return a}

		main :: proc () {
			a: Vec
			f{*} := foo(a)
		}
		`}},
	}

	test.expect_type_definition_locations(t, &source)
}

@(test)
ast_type_definition_package_proc :: proc(t: ^testing.T) {
	packages := make([dynamic]test.FileInPackage, context.temp_allocator)

	append(
		&packages,
		test.FileInPackage {
			pkg = "my_package",
			source = `package my_package
		{:}Foo{:} :: struct {x, y: i32}

		get_foo :: proc () -> Foo {return {}}
		`,
		},
	)

	inject_at(&packages, 0, test.FileInPackage{source = `package test
		import "my_package"

		main :: proc () {
			f{*}oo := my_package.get_foo()
		}
		`})
source := test.Source {
	files = packages[:],
	}

	test.expect_type_definition_locations(t, &source)
}
