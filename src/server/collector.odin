#+feature using-stmt
package server

import "core:mem"
import "core:odin/ast"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strings"

import "src:analysis"
import "src:common"

collect_procedure_fields :: proc(
	collection: ^analysis.SymbolCollection,
	proc_type: ^ast.Proc_Type,
	arg_list: ^ast.Field_List,
	return_list: ^ast.Field_List,
	package_map: map[string]string,
	attributes: []^ast.Attribute,
	inlining: ast.Proc_Inlining,
	where_clauses: []^ast.Expr,
) -> analysis.SymbolProcedureValue {
	returns := make([dynamic]^ast.Field, 0)
	args := make([dynamic]^ast.Field, 0)
	attrs := make([dynamic]^ast.Attribute, 0)

	if return_list != nil {
		for ret in return_list.list {
			cloned := cast(^ast.Field)analysis.clone_type(ret, &collection.unique_strings)
			replace_package_alias(cloned, package_map, collection)
			append(&returns, cloned)
		}
	}

	if arg_list != nil {
		for arg in arg_list.list {
			cloned := cast(^ast.Field)analysis.clone_type(arg, &collection.unique_strings)
			replace_package_alias(cloned, package_map, collection)
			append(&args, cloned)
		}
	}

	for attr in attributes {
		cloned := cast(^ast.Attribute)analysis.clone_type(attr, &collection.unique_strings)
		append(&attrs, cloned)
	}

	value := analysis.SymbolProcedureValue {
		return_types       = returns[:],
		orig_return_types  = returns[:],
		arg_types          = args[:],
		orig_arg_types     = args[:],
		generic            = is_procedure_generic(proc_type),
		diverging          = proc_type.diverging,
		calling_convention = analysis.clone_calling_convention(proc_type.calling_convention, &collection.unique_strings),
		tags               = proc_type.tags,
		attributes         = attrs[:],
		inlining           = inlining,
		where_clauses      = analysis.clone_array(where_clauses, &collection.unique_strings),
	}

	return value
}

collect_struct_fields :: proc(
	collection: ^analysis.SymbolCollection,
	struct_type: ^ast.Struct_Type,
	package_map: map[string]string,
	file: ast.File,
) -> analysis.SymbolStructValue {
	b := analysis.symbol_struct_value_builder_make()
	construct_struct_field_docs(file, struct_type)

	for field in struct_type.fields.list {
		for n in field.names {
			if ident, ok := n.derived.(^ast.Ident); ok {
				append(&b.names, analysis.get_index_unique_string(collection, ident.name))

				cloned := analysis.clone_type(field.type, &collection.unique_strings)
				replace_package_alias(cloned, package_map, collection)
				append(&b.types, cloned)

				if .Using in field.flags {
					append(&b.unexpanded_usings, len(b.names) - 1)
					append(&b.usings, len(b.names) - 1)
				}

				append(&b.ranges, common.get_token_range(n, file.src))

				cloned_docs := analysis.clone_type(field.docs, &collection.unique_strings)
				append(&b.docs, cloned_docs)
				cloned_comment := analysis.clone_type(field.comment, &collection.unique_strings)
				append(&b.comments, cloned_comment)
				append(&b.from_usings, -1)
			}
		}
	}

	b.align = analysis.clone_expr(struct_type.align, &collection.unique_strings)
	b.max_field_align = analysis.clone_expr(struct_type.max_field_align, &collection.unique_strings)
	b.min_field_align = analysis.clone_expr(struct_type.min_field_align, &collection.unique_strings)
	if struct_type.is_all_or_none {
		b.tags |= {.Is_All_Or_None}
	}
	if struct_type.is_no_copy {
		b.tags |= {.Is_No_Copy}
	}
	if struct_type.is_packed {
		b.tags |= {.Is_Packed}
	}
	if struct_type.is_raw_union {
		b.tags |= {.Is_Raw_Union}
	}

	b.poly = cast(^ast.Field_List)analysis.clone_type(struct_type.poly_params, &collection.unique_strings)
	for clause in struct_type.where_clauses {
		append(&b.where_clauses, analysis.clone_expr(clause, &collection.unique_strings))
	}
	value := analysis.to_symbol_struct_value(b)

	return value
}

collect_bit_field_fields :: proc(
	collection: ^analysis.SymbolCollection,
	bit_field_type: ^ast.Bit_Field_Type,
	package_map: map[string]string,
	file: ast.File,
) -> analysis.SymbolBitFieldValue {
	construct_bit_field_field_docs(file, bit_field_type)
	names := make([dynamic]string, 0, len(bit_field_type.fields))
	types := make([dynamic]^ast.Expr, 0, len(bit_field_type.fields))
	ranges := make([dynamic]common.Range, 0, len(bit_field_type.fields))
	docs := make([dynamic]^ast.Comment_Group, 0)
	comments := make([dynamic]^ast.Comment_Group, 0)
	bit_sizes := make([dynamic]^ast.Expr, 0)

	for field, i in bit_field_type.fields {
		if ident, ok := field.name.derived.(^ast.Ident); ok {
			append(&names, analysis.get_index_unique_string(collection, ident.name))

			cloned := analysis.clone_type(field.type, &collection.unique_strings)
			replace_package_alias(cloned, package_map, collection)
			append(&types, cloned)

			append(&ranges, common.get_token_range(ident, file.src))
			append(&docs, analysis.clone_comment_group(field.docs, &collection.unique_strings))
			append(&comments, analysis.clone_comment_group(field.comments, &collection.unique_strings))
			append(&bit_sizes, analysis.clone_type(field.bit_size, &collection.unique_strings))
		}
	}

	value := analysis.SymbolBitFieldValue {
		backing_type = analysis.clone_type(bit_field_type.backing_type, &collection.unique_strings),
		names        = names[:],
		types        = types[:],
		ranges       = ranges[:],
		docs         = docs[:],
		comments     = comments[:],
		bit_sizes    = bit_sizes[:],
	}

	return value
}

collect_enum_fields :: proc(
	collection: ^analysis.SymbolCollection,
	enum_type: ast.Enum_Type,
	package_map: map[string]string,
	file: ast.File,
) -> analysis.SymbolEnumValue {
	names := make([dynamic]string, 0)
	ranges := make([dynamic]common.Range, 0)
	values := make([dynamic]^ast.Expr, 0)

	for n in enum_type.fields {
		name, range, value := get_enum_field_name_range_value(n, file.src)
		append(&names, strings.clone(name))
		append(&ranges, range)
		append(&values, analysis.clone_type(value, &collection.unique_strings))
	}

	temp_docs, temp_comments := get_field_docs_and_comments(file, enum_type.fields)
	docs := analysis.clone_dynamic_array(temp_docs, &collection.unique_strings)
	comments := analysis.clone_dynamic_array(temp_comments, &collection.unique_strings)

	value := analysis.SymbolEnumValue {
		names     = names[:],
		ranges    = ranges[:],
		values    = values[:],
		base_type = analysis.clone_type(enum_type.base_type, &collection.unique_strings),
		comments  = comments[:],
		docs      = docs[:],
	}

	return value
}

collect_union_fields :: proc(
	collection: ^analysis.SymbolCollection,
	union_type: ast.Union_Type,
	package_map: map[string]string,
	file: ast.File,
) -> analysis.SymbolUnionValue {
	types := make([dynamic]^ast.Expr, 0)

	for variant in union_type.variants {
		cloned := analysis.clone_type(variant, &collection.unique_strings)
		replace_package_alias(cloned, package_map, collection)
		append(&types, cloned)
	}

	temp_docs, temp_comments := get_field_docs_and_comments(file, union_type.variants)
	docs := analysis.clone_dynamic_array(temp_docs, &collection.unique_strings)
	comments := analysis.clone_dynamic_array(temp_comments, &collection.unique_strings)

	value := analysis.SymbolUnionValue {
		types         = types[:],
		poly          = cast(^ast.Field_List)analysis.clone_type(union_type.poly_params, &collection.unique_strings),
		comments      = comments[:],
		docs          = docs[:],
		kind          = union_type.kind,
		align         = analysis.clone_type(union_type.align, &collection.unique_strings),
		where_clauses = analysis.clone_array(union_type.where_clauses, &collection.unique_strings),
	}

	return value
}

collect_bitset_field :: proc(
	collection: ^analysis.SymbolCollection,
	bitset_type: ast.Bit_Set_Type,
	package_map: map[string]string,
) -> analysis.SymbolBitSetValue {
	cloned := analysis.clone_type(bitset_type.elem, &collection.unique_strings)
	replace_package_alias(cloned, package_map, collection)

	return analysis.SymbolBitSetValue{expr = cloned}
}

collect_slice :: proc(
	collection: ^analysis.SymbolCollection,
	array: ast.Array_Type,
	package_map: map[string]string,
) -> analysis.SymbolSliceValue {
	elem := analysis.clone_type(array.elem, &collection.unique_strings)

	replace_package_alias(elem, package_map, collection)

	return analysis.SymbolSliceValue{expr = elem}
}

collect_array :: proc(
	collection: ^analysis.SymbolCollection,
	array: ast.Array_Type,
	package_map: map[string]string,
) -> analysis.SymbolFixedArrayValue {
	elem := analysis.clone_type(array.elem, &collection.unique_strings)
	len := analysis.clone_type(array.len, &collection.unique_strings)

	replace_package_alias(elem, package_map, collection)
	replace_package_alias(len, package_map, collection)

	return analysis.SymbolFixedArrayValue{expr = elem, len = len}
}

collect_map :: proc(collection: ^analysis.SymbolCollection, m: ast.Map_Type, package_map: map[string]string) -> analysis.SymbolMapValue {
	key := analysis.clone_type(m.key, &collection.unique_strings)
	value := analysis.clone_type(m.value, &collection.unique_strings)

	replace_package_alias(key, package_map, collection)
	replace_package_alias(value, package_map, collection)

	return analysis.SymbolMapValue{key = key, value = value}
}

collect_dynamic_array :: proc(
	collection: ^analysis.SymbolCollection,
	array: ast.Dynamic_Array_Type,
	package_map: map[string]string,
) -> analysis.SymbolDynamicArrayValue {
	elem := analysis.clone_type(array.elem, &collection.unique_strings)

	replace_package_alias(elem, package_map, collection)

	return analysis.SymbolDynamicArrayValue{expr = elem}
}

collect_matrix :: proc(
	collection: ^analysis.SymbolCollection,
	mat: ast.Matrix_Type,
	package_map: map[string]string,
) -> analysis.SymbolMatrixValue {
	elem := analysis.clone_type(mat.elem, &collection.unique_strings)

	y := analysis.clone_type(mat.column_count, &collection.unique_strings)

	x := analysis.clone_type(mat.row_count, &collection.unique_strings)

	replace_package_alias(elem, package_map, collection)
	replace_package_alias(x, package_map, collection)
	replace_package_alias(y, package_map, collection)

	return analysis.SymbolMatrixValue{expr = elem, x = x, y = y}
}

collect_multi_pointer :: proc(
	collection: ^analysis.SymbolCollection,
	array: ast.Multi_Pointer_Type,
	package_map: map[string]string,
) -> analysis.SymbolMultiPointerValue {
	elem := analysis.clone_type(array.elem, &collection.unique_strings)

	replace_package_alias(elem, package_map, collection)

	return analysis.SymbolMultiPointerValue{expr = elem}
}


collect_generic :: proc(
	collection: ^analysis.SymbolCollection,
	expr: ^ast.Expr,
	package_map: map[string]string,
	uri: string,
) -> analysis.SymbolGenericValue {
	//Bit hacky right now, but it's hopefully a temporary solution.
	//In the c package code it uses a documentation package(builtin).
	if selector, ok := expr.derived.(^ast.Selector_Expr); ok {
		if ident, ok := selector.expr.derived.(^ast.Ident); ok {
			if ident.name == "builtin" && strings.contains(uri, "/core/c/c.odin") {
				cloned := analysis.clone_type(selector.field, &collection.unique_strings)
				replace_package_alias(cloned, package_map, collection)
				value := analysis.SymbolGenericValue {
					expr = cloned,
				}
				return value
			}
		}
	}

	cloned := analysis.clone_type(expr, &collection.unique_strings)
	replace_package_alias(cloned, package_map, collection)

	value := analysis.SymbolGenericValue {
		expr = cloned,
	}

	return value
}

add_comp_lit_fields :: proc(
	collection: ^analysis.SymbolCollection,
	generic: ^analysis.SymbolGenericValue,
	comp_lit_type: ^ast.Comp_Lit,
	package_map: map[string]string,
	file: ast.File,
) {
	names := make([dynamic]string, 0, len(comp_lit_type.elems))
	ranges := make([dynamic]common.Range, 0, len(comp_lit_type.elems))
	for elem in comp_lit_type.elems {
		if field_value, ok := elem.derived.(^ast.Field_Value); ok {
			if ident, ok := field_value.field.derived.(^ast.Ident); ok {
				name := analysis.get_index_unique_string(collection, ident.name)
				append(&names, name)
				append(&ranges, common.get_token_range(field_value, file.src))
			}
		}
	}
	generic.field_names = names[:]
	generic.ranges = ranges[:]
}

/*
	Records the names of procedures that are part of a proc group.
	This is used by the fake methods feature to hide individual procs
	when the proc group should be shown instead.
*/
record_proc_group_members :: proc(collection: ^analysis.SymbolCollection, group: ^ast.Proc_Group, pkg_name: string) {
	pkg := analysis.get_or_create_package(collection, pkg_name)

	for arg in group.args {
		name := get_proc_group_member_name(arg) or_continue
		pkg.proc_group_members[analysis.get_index_unique_string(collection, name)] = true
	}
}

@(private = "file")
get_proc_group_member_name :: proc(expr: ^ast.Expr) -> (name: string, ok: bool) {
	#partial switch v in expr.derived {
	case ^ast.Ident:
		return v.name, true
	case ^ast.Selector_Expr:
		// For package.proc_name, we only care about the proc name
		if field, is_ident := v.field.derived.(^ast.Ident); is_ident {
			return field.name, true
		}
	}
	return "", false
}

/*
	Collects a procedure as a fake method if it's not part of a proc group.
*/
collect_method :: proc(collection: ^analysis.SymbolCollection, symbol: analysis.Symbol) {
	pkg := &collection.packages[symbol.pkg]

	if symbol.name in pkg.proc_group_members {
		return
	}

	value, ok := symbol.value.(analysis.SymbolProcedureValue)
	if !ok {
		return
	}
	if len(value.arg_types) == 0 {
		return
	}

	method, method_ok := get_method_from_first_arg(collection, value.arg_types[0].type, symbol.pkg)
	if !method_ok {
		return
	}
	add_symbol_to_method(collection, pkg, method, symbol)
}

/*
	Collects a proc group as a fake method based on its member procedures' first arguments.
	The proc group is registered as a method for each distinct first-argument type
	across all its members.
*/
collect_proc_group_method :: proc(collection: ^analysis.SymbolCollection, symbol: analysis.Symbol) {
	pkg := &collection.packages[symbol.pkg]

	group_value, ok := symbol.value.(analysis.SymbolProcedureGroupValue)
	if !ok {
		return
	}

	proc_group, is_proc_group := group_value.group.derived.(^ast.Proc_Group)
	if !is_proc_group || len(proc_group.args) == 0 {
		return
	}

	// Track which method keys we've already registered to avoid duplicates
	registered_methods := make(map[analysis.Method]bool, len(proc_group.args), context.temp_allocator)

	// Register the proc group as a method for each distinct first-argument type
	for member_expr in proc_group.args {
		member_name, name_ok := get_proc_group_member_name(member_expr)
		if !name_ok {
			continue
		}

		member_symbol, found := pkg.symbols[member_name]
		if !found {
			continue
		}

		member_proc, is_proc := member_symbol.value.(analysis.SymbolProcedureValue)
		if !is_proc || len(member_proc.arg_types) == 0 {
			continue
		}

		method, method_ok := get_method_from_first_arg(collection, member_proc.arg_types[0].type, symbol.pkg)
		if !method_ok {
			continue
		}

		if method not_in registered_methods {
			registered_methods[method] = true
			add_symbol_to_method(collection, pkg, method, symbol)
		}
	}
}

@(private = "file")
get_method_from_first_arg :: proc(
	collection: ^analysis.SymbolCollection,
	first_arg_type: ^ast.Expr,
	default_pkg: string,
) -> (
	method: analysis.Method,
	ok: bool,
) {
	expr, _, unwrap_ok := unwrap_pointer_ident(first_arg_type)
	if !unwrap_ok {
		return {}, false
	}

	#partial switch v in expr.derived {
	case ^ast.Selector_Expr:
		ident, is_ident := v.expr.derived.(^ast.Ident)
		if !is_ident {
			return {}, false
		}
		method.pkg = analysis.get_index_unique_string(collection, ident.name)
		method.name = analysis.get_index_unique_string(collection, v.field.name)
	case ^ast.Ident:
		if is_builtin_type_name(v.name) {
			method.pkg = "$builtin"
		} else {
			method.pkg = default_pkg
		}
		method.name = analysis.get_index_unique_string(collection, v.name)
	case:
		return {}, false
	}

	return method, true
}

is_builtin_type_name :: proc(name: string) -> bool {
	for names in untyped_map {
		for builtin_name in names {
			if name == builtin_name {
				return true
			}
		}
	}
	// Also check some other builtin types not in untyped_map
	switch name {
	case "rawptr", "uintptr", "typeid", "any", "rune":
		return true
	}
	return false
}

@(private = "file")
add_symbol_to_method :: proc(collection: ^analysis.SymbolCollection, pkg: ^analysis.SymbolPackage, method: analysis.Method, symbol: analysis.Symbol) {
	symbols := &pkg.methods[method]
	if symbols == nil {
		pkg.methods[method] = make([dynamic]analysis.Symbol)
		symbols = &pkg.methods[method]
	}
	append(symbols, symbol)
}

collect_objc :: proc(collection: ^analysis.SymbolCollection, attributes: []^ast.Attribute, symbol: analysis.Symbol) {
	pkg := &collection.packages[symbol.pkg]

	if value, ok := symbol.value.(analysis.SymbolProcedureValue); ok {
		objc_name, found_objc_name := get_attribute_objc_name(attributes)

		if objc_type := get_attribute_objc_type(attributes); objc_type != nil && found_objc_name {

			if struct_ident, ok := objc_type.derived.(^ast.Ident); ok {
				struct_name := analysis.get_index_unique_string_collection(collection, struct_ident.name)

				objc_struct := &pkg.objc_structs[struct_name]

				if objc_struct == nil {
					pkg.objc_structs[struct_name] = {}
					objc_struct = &pkg.objc_structs[struct_name]
					objc_struct.functions = make([dynamic]analysis.ObjcFunction, 0, 10)
					objc_struct.ranges = make([dynamic]common.Range, 0, 10)
					objc_struct.pkg = symbol.pkg
				}

				append(&objc_struct.ranges, symbol.range)

				append(
					&objc_struct.functions,
					analysis.ObjcFunction {
						logical_name = analysis.get_index_unique_string_collection(collection, objc_name),
						physical_name = symbol.name,
					},
				)
			}
		}
	}
}

collect_imports :: proc(collection: ^analysis.SymbolCollection, file: ast.File, directory: string) {
	_pkg := analysis.get_index_unique_string(collection, directory)

	if _pkg, ok := collection.packages[_pkg]; ok {

	}

}


collect_symbols :: proc(collection: ^analysis.SymbolCollection, file: ast.File, uri: string) -> common.Error {
	forward, _ := filepath.to_slash(file.fullpath, context.temp_allocator)
	directory := path.dir(forward, context.temp_allocator)
	package_map := get_package_mapping(file, collection.config, directory)
	exprs := collect_globals(file)

	for expr in exprs {
		symbol: analysis.Symbol

		token: ast.Node
		token_type: analysis.SymbolType

		name := expr.name

		col_expr := expr.expr

		if helper, ok := col_expr.derived.(^ast.Helper_Type); ok {
			if helper.type != nil {
				col_expr = helper.type
			}
		}
		is_distinct := false

		if dist, ok := col_expr.derived.(^ast.Distinct_Type); ok {
			if dist.type != nil {
				col_expr = dist.type
				is_distinct = true
			}
		}

		// Compute pkg early so it's available inside the switch
		if expr.builtin || strings.contains(uri, "builtin.odin") {
			symbol.pkg = "$builtin"
		} else if strings.contains(uri, "intrinsics.odin") {
			intrinsics_path := filepath.join(
				elems = {common.config.collections["base"], "/intrinsics"},
				allocator = context.temp_allocator,
			)
			intrinsics_path, _ = filepath.to_slash(intrinsics_path, context.temp_allocator)
			symbol.pkg = analysis.get_index_unique_string(collection, intrinsics_path)
		} else {
			symbol.pkg = analysis.get_index_unique_string(collection, directory)
		}

		#partial switch v in col_expr.derived {
		case ^ast.Matrix_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_matrix(collection, v^, package_map)
		case ^ast.Proc_Lit:
			token = v^
			token_type = .Function

			if v.type != nil {
				symbol.value = collect_procedure_fields(
					collection,
					v.type,
					v.type.params,
					v.type.results,
					package_map,
					expr.attributes,
					v.inlining,
					v.where_clauses,
				)
			}

			if _, is_objc := get_attribute_objc_name(expr.attributes); is_objc {
				symbol.flags |= {.ObjC}
				if get_attribute_objc_is_class_method(expr.attributes) {
					symbol.flags |= {.ObjCIsClassMethod}
				}
			}
		case ^ast.Proc_Type:
			token = v^
			token_type = .Type_Function
			symbol.value = collect_procedure_fields(
				collection,
				cast(^ast.Proc_Type)col_expr,
				v.params,
				v.results,
				package_map,
				expr.attributes,
				.None,
				nil,
			)
		case ^ast.Proc_Group:
			token = v^
			token_type = .Function
			symbol.value = analysis.SymbolProcedureGroupValue {
				group = analysis.clone_type(col_expr, &collection.unique_strings),
			}
			// Record proc group members for fake methods feature
			if collection.config != nil && collection.config.enable_fake_method {
				record_proc_group_members(collection, v, symbol.pkg)
			}
		case ^ast.Struct_Type:
			token = v^
			token_type = .Struct
			symbol.value = collect_struct_fields(collection, v, package_map, file)
			symbol.signature = "struct"

			if _, is_objc := get_attribute_objc_class_name(expr.attributes); is_objc {
				symbol.flags |= {.ObjC}
				if get_attribute_objc_is_class_method(expr.attributes) {
					symbol.flags |= {.ObjCIsClassMethod}
				}
			}
		case ^ast.Enum_Type:
			token = v^
			token_type = .Enum
			symbol.value = collect_enum_fields(collection, v^, package_map, file)
			symbol.signature = "enum"
		case ^ast.Union_Type:
			token = v^
			token_type = .Union
			symbol.value = collect_union_fields(collection, v^, package_map, file)
			symbol.signature = "union"
		case ^ast.Bit_Set_Type:
			token = v^
			token_type = .Enum
			symbol.value = collect_bitset_field(collection, v^, package_map)
			symbol.signature = "bitset"
		case ^ast.Bit_Field_Type:
			token = v^
			token_type = .Struct
			symbol.value = collect_bit_field_fields(collection, v, package_map, file)
			symbol.signature = "bit_field"
		case ^ast.Map_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_map(collection, v^, package_map)
		case ^ast.Array_Type:
			token = v^
			token_type = .Type
			if v.len == nil {
				symbol.value = collect_slice(collection, v^, package_map)
			} else {
				symbol.value = collect_array(collection, v^, package_map)
			}
		case ^ast.Dynamic_Array_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_dynamic_array(collection, v^, package_map)
		case ^ast.Multi_Pointer_Type:
			token = v^
			token_type = .Type
			symbol.value = collect_multi_pointer(collection, v^, package_map)
		case ^ast.Typeid_Type:
			if v.specialization == nil {
				continue
			}

			ident := analysis.new_type(ast.Ident, v.pos, v.end)
			ident.name = "typeid"

			symbol.value = collect_generic(collection, ident, package_map, uri)
		case ^ast.Basic_Lit:
			token = v^
			symbol.value = collect_generic(collection, col_expr, package_map, uri)
			token_type = .Unresolved
		case ^ast.Ident:
			token = v^
			symbol.value = collect_generic(collection, col_expr, package_map, uri)

			if .Mutable in expr.flags {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}
		case ^ast.Comp_Lit:
			generic := collect_generic(collection, col_expr, package_map, uri)

			if .Mutable in expr.flags {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}

			token = expr.expr

			add_comp_lit_fields(collection, &generic, v, package_map, file)
			symbol.value = generic
		case:
			// default
			symbol.value = collect_generic(collection, col_expr, package_map, uri)

			if .Mutable in expr.flags {
				token_type = .Variable
			} else {
				token_type = .Unresolved
			}

			token = expr.expr
		}


		symbol.range = common.get_token_range(expr.name_expr, file.src)
		symbol.name = analysis.get_index_unique_string(collection, name)
		symbol.type = token_type
		symbol.doc = get_comment(expr.docs)
		symbol.uri = analysis.get_index_unique_string(collection, uri)
		symbol.type_expr = analysis.clone_type(expr.type_expr, &collection.unique_strings)
		symbol.value_expr = analysis.clone_type(expr.value_expr, &collection.unique_strings)
		comment, _ := get_file_comment(file, symbol.range.start.line + 1)
		symbol.comment = get_comment(comment)

		// symbol.pkg was already set earlier before the switch

		if is_distinct {
			symbol.flags |= {.Distinct}
		}

		if expr.builtin {
			symbol.flags |= {.Builtin}
		}

		if expr.deprecated {
			symbol.flags |= {.Deprecated}
		}

		if expr.private == .File {
			symbol.flags |= {.PrivateFile}
		}

		if expr.private == .Package {
			symbol.flags |= {.PrivatePackage}
		}

		if .Variable in expr.flags {
			symbol.flags |= {.Variable}
		}

		if .Mutable in expr.flags {
			symbol.flags |= {.Mutable}
		}

		pkg: ^analysis.SymbolPackage
		ok: bool

		if pkg, ok = &collection.packages[symbol.pkg]; !ok {
			collection.packages[symbol.pkg] = {}
			pkg = &collection.packages[symbol.pkg]
			pkg.symbols = make(map[string]analysis.Symbol, 100)
			pkg.methods = make(map[analysis.Method][dynamic]analysis.Symbol, 100)
			pkg.objc_structs = make(map[string]analysis.ObjcStruct, 5)
			pkg.proc_group_members = make(map[string]bool, 10)
		}

		if .ObjC in symbol.flags {
			collect_objc(collection, expr.attributes, symbol)
		}

		if v, ok := pkg.symbols[symbol.name]; !ok || v.name == "" {
			pkg.symbols[symbol.name] = symbol
		}
	}

	// Second pass: collect fake methods after all symbols and proc group members are recorded
	if collection.config != nil && collection.config.enable_fake_method {
		collect_fake_methods(collection, exprs, directory, uri)
	}

	collect_imports(collection, file, directory)


	return .None
}

/*
	Collects fake methods for all procedures and proc groups.
	This is done as a second pass after all symbols are collected,
	so that we know which procedures are part of proc groups.
*/
@(private = "file")
collect_fake_methods :: proc(collection: ^analysis.SymbolCollection, exprs: []GlobalExpr, directory: string, uri: string) {
	for expr in exprs {
		// Determine the package name (same logic as in collect_symbols)
		pkg_name: string
		if expr.builtin || strings.contains(uri, "builtin.odin") {
			pkg_name = "$builtin"
		} else if strings.contains(uri, "intrinsics.odin") {
			intrinsics_path := filepath.join(
				elems = {common.config.collections["base"], "/intrinsics"},
				allocator = context.temp_allocator,
			)
			intrinsics_path, _ = filepath.to_slash(intrinsics_path, context.temp_allocator)
			pkg_name = analysis.get_index_unique_string(collection, intrinsics_path)
		} else {
			pkg_name = analysis.get_index_unique_string(collection, directory)
		}

		pkg, ok := &collection.packages[pkg_name]
		if !ok {
			continue
		}

		symbol, found := pkg.symbols[expr.name]
		if !found {
			continue
		}

		#partial switch _ in symbol.value {
		case analysis.SymbolProcedureValue:
			collect_method(collection, symbol)
		case analysis.SymbolProcedureGroupValue:
			collect_proc_group_method(collection, symbol)
		}
	}
}

Reference :: struct {
	identifiers: [dynamic]common.Location,
	selectors:   map[string][dynamic]common.Range,
}

/*
	Gets the map from import alias to absolute package directory
*/
get_package_mapping :: proc(file: ast.File, config: ^common.Config, directory: string) -> map[string]string {
	package_map := make(map[string]string, 0, context.temp_allocator)

	for imp, index in file.imports {
		//collection specified
		if len(imp.fullpath) < 2 {
			continue
		}

		if i := strings.index(imp.fullpath, ":"); i != -1 && i != len(imp.fullpath) - 1 {
			collection := imp.fullpath[1:i]
			p := imp.fullpath[i + 1:len(imp.fullpath) - 1]

			dir, ok := config.collections[collection]

			if !ok {
				continue
			}

			name: string

			full := path.join(elems = {dir, p}, allocator = context.temp_allocator)

			if imp.name.text != "" {
				name = imp.name.text
			} else {
				name = path.base(full, false, context.temp_allocator)
			}

			package_map[name] = full
		} else {
			name: string

			full := path.join(
				elems = {directory, imp.fullpath[1:len(imp.fullpath) - 1]},
				allocator = context.temp_allocator,
			)
			full = path.clean(full, context.temp_allocator)

			if imp.name.text != "" {
				name = imp.name.text
			} else {
				name = path.base(full, false, context.temp_allocator)
			}

			package_map[name] = full
		}
	}

	return package_map
}

/*
	We can't have the alias names for packages with selector expression since that is specific to every files import, instead just replace it with the absolute
	package name(absolute directory path)
*/

replace_package_alias :: proc {
	replace_package_alias_node,
	replace_package_alias_expr,
	replace_package_alias_array,
	replace_package_alias_dynamic_array,
}

replace_package_alias_array :: proc(array: $A/[]^$T, package_map: map[string]string, collection: ^analysis.SymbolCollection) {
	for elem, i in array {
		replace_package_alias(elem, package_map, collection)
	}
}

replace_package_alias_dynamic_array :: proc(
	array: $A/[dynamic]^$T,
	package_map: map[string]string,
	collection: ^analysis.SymbolCollection,
) {
	for elem, i in array {
		replace_package_alias(elem, package_map, collection)
	}
}

replace_package_alias_expr :: proc(node: ^ast.Expr, package_map: map[string]string, collection: ^analysis.SymbolCollection) {
	replace_package_alias_node(node, package_map, collection)
}

replace_package_alias_node :: proc(node: ^ast.Node, package_map: map[string]string, collection: ^analysis.SymbolCollection) {
	using ast

	if node == nil {
		return
	}

	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
	case ^Implicit:
	case ^Undef:
	case ^Basic_Lit:
	case ^Basic_Directive:
	case ^Ellipsis:
		replace_package_alias(n.expr, package_map, collection)
	case ^Tag_Expr:
		replace_package_alias(n.expr, package_map, collection)
	case ^Unary_Expr:
		replace_package_alias(n.expr, package_map, collection)
	case ^Binary_Expr:
		replace_package_alias(n.left, package_map, collection)
		replace_package_alias(n.right, package_map, collection)
	case ^Paren_Expr:
		replace_package_alias(n.expr, package_map, collection)
	case ^Selector_Expr:
		if _, ok := n.expr.derived.(^Ident); ok {
			ident := n.expr.derived.(^Ident)

			if package_name, ok := package_map[ident.name]; ok {
				ident.name = analysis.get_index_unique_string(collection, package_name)
			}
		} else {
			replace_package_alias(n.expr, package_map, collection)
			replace_package_alias(n.field, package_map, collection)
		}
	case ^Implicit_Selector_Expr:
		replace_package_alias(n.field, package_map, collection)
	case ^Slice_Expr:
		replace_package_alias(n.expr, package_map, collection)
		replace_package_alias(n.low, package_map, collection)
		replace_package_alias(n.high, package_map, collection)
	case ^Attribute:
		replace_package_alias(n.elems, package_map, collection)
	case ^Distinct_Type:
		replace_package_alias(n.type, package_map, collection)
	case ^Proc_Type:
		replace_package_alias(n.params, package_map, collection)
		replace_package_alias(n.results, package_map, collection)
	case ^Pointer_Type:
		replace_package_alias(n.elem, package_map, collection)
	case ^Array_Type:
		replace_package_alias(n.len, package_map, collection)
		replace_package_alias(n.elem, package_map, collection)
	case ^Dynamic_Array_Type:
		replace_package_alias(n.elem, package_map, collection)
	case ^Struct_Type:
		replace_package_alias(n.poly_params, package_map, collection)
		replace_package_alias(n.align, package_map, collection)
		replace_package_alias(n.fields, package_map, collection)
	case ^Field:
		replace_package_alias(n.names, package_map, collection)
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.default_value, package_map, collection)
	case ^Field_List:
		replace_package_alias(n.list, package_map, collection)
	case ^Field_Value:
		replace_package_alias(n.field, package_map, collection)
		replace_package_alias(n.value, package_map, collection)
	case ^Union_Type:
		replace_package_alias(n.poly_params, package_map, collection)
		replace_package_alias(n.align, package_map, collection)
		replace_package_alias(n.variants, package_map, collection)
	case ^Enum_Type:
		replace_package_alias(n.base_type, package_map, collection)
		replace_package_alias(n.fields, package_map, collection)
	case ^Bit_Set_Type:
		replace_package_alias(n.elem, package_map, collection)
		replace_package_alias(n.underlying, package_map, collection)
	case ^Map_Type:
		replace_package_alias(n.key, package_map, collection)
		replace_package_alias(n.value, package_map, collection)
	case ^Call_Expr:
		replace_package_alias(n.expr, package_map, collection)
		replace_package_alias(n.args, package_map, collection)
	case ^Typeid_Type:
		replace_package_alias(n.specialization, package_map, collection)
	case ^Poly_Type:
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.specialization, package_map, collection)
	case ^Proc_Group:
		replace_package_alias(n.args, package_map, collection)
	case ^Comp_Lit:
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.elems, package_map, collection)
	case ^Helper_Type:
		replace_package_alias(n.type, package_map, collection)
	case ^Proc_Lit:
	case ^Multi_Pointer_Type:
		replace_package_alias(n.elem, package_map, collection)
	case ^Bit_Field_Type:
		replace_package_alias(n.backing_type, package_map, collection)
		replace_package_alias(n.fields, package_map, collection)
	case ^Bit_Field_Field:
		replace_package_alias(n.name, package_map, collection)
		replace_package_alias(n.type, package_map, collection)
		replace_package_alias(n.bit_size, package_map, collection)
	case:
	}
}
