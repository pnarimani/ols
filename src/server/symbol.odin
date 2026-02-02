#+feature using-stmt
package server

import "core:mem"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:slice"

import "src:analysis"
import "src:common"

write_struct_type :: proc(
	ast_context: ^AstContext,
	b: ^analysis.SymbolStructValueBuilder,
	v: ^ast.Struct_Type,
	attributes: []^ast.Attribute,
	base_using_index: int,
) {
	using analysis
	b.poly = v.poly_params
	// We clone this so we don't override docs and comments with temp allocated docs and comments
	v := cast(^ast.Struct_Type)analysis.clone_node(v, nil)
	construct_struct_field_docs(ast_context.file, v)
	for field in v.fields.list {
		for n in field.names {
			if identifier, ok := n.derived.(^ast.Ident); ok && field.type != nil {
				if .Using in field.flags {
					append(&b.unexpanded_usings, len(b.types))
					append(&b.usings, len(b.types))
				}

				append(&b.names, identifier.name)
				if v.poly_params != nil {
					append(&b.types, analysis.clone_type(field.type, nil))
				} else {
					append(&b.types, field.type)
				}

				append(&b.ranges, common.get_token_range(n, ast_context.file.src))
				append(&b.docs, field.docs)
				append(&b.comments, field.comment)
				append(&b.from_usings, base_using_index)
			}
		}
	}

	if _, ok := get_attribute_objc_class_name(attributes); ok {
		b.symbol.flags |= {.ObjC}
		if get_attribute_objc_is_class_method(attributes) {
			b.symbol.flags |= {.ObjCIsClassMethod}
		}
	}

	if v.poly_params != nil {
		resolve_poly_struct(ast_context, b, v.poly_params)
	}

	if base_using_index == -1 {
		// only map tags for the base struct
		b.align = v.align
		b.max_field_align = v.max_field_align
		b.min_field_align = v.min_field_align
		if v.is_all_or_none {
			b.tags |= {.Is_All_Or_None}
		}
		if v.is_no_copy {
			b.tags |= {.Is_No_Copy}
		}
		if v.is_packed {
			b.tags |= {.Is_Packed}
		}
		if v.is_raw_union {
			b.tags |= {.Is_Raw_Union}
		}
		for clause in v.where_clauses {
			append(&b.where_clauses, clause)
		}
	}

	expand_objc(ast_context, b)
	expand_usings(ast_context, b)
}

write_symbol_struct_value :: proc(
	ast_context: ^AstContext,
	b: ^analysis.SymbolStructValueBuilder,
	v: analysis.SymbolStructValue,
	base_using_index: int,
) {
	base_index := len(b.names)
	for name in v.names {
		append(&b.names, name)
	}
	for type in v.types {
		append(&b.types, type)
	}
	for arg in v.args {
		append(&b.args, arg)
	}
	for range in v.ranges {
		append(&b.ranges, range)
	}
	for doc in v.docs {
		append(&b.docs, doc)
	}
	for comment in v.comments {
		append(&b.comments, comment)
	}
	for u in v.from_usings {
		if u == -1 {
			append(&b.from_usings, base_using_index)
		} else {
			append(&b.from_usings, u + base_index)
		}
	}
	for u in v.unexpanded_usings {
		append(&b.unexpanded_usings, u + base_index)
	}
	for k, value in v.backing_types {
		b.backing_types[k + base_index] = value
	}
	for k, value in v.bit_sizes {
		b.bit_sizes[k + base_index] = value
	}
	for k in v.usings {
		append(&b.usings, k + base_index)
	}
	expand_usings(ast_context, b)
}

write_symbol_bitfield_value :: proc(
	ast_context: ^AstContext,
	b: ^analysis.SymbolStructValueBuilder,
	v: analysis.SymbolBitFieldValue,
	base_using_index: int,
) {
	base_index := len(b.names)
	for name, i in v.names {
		append(&b.names, name)
		append(&b.from_usings, base_using_index)
	}
	for type in v.types {
		append(&b.types, type)
	}
	for range in v.ranges {
		append(&b.ranges, range)
	}
	for doc in v.docs {
		append(&b.docs, doc)
	}
	for comment in v.comments {
		append(&b.comments, comment)
	}
	b.backing_types[base_using_index] = v.backing_type
	for bit_size, i in v.bit_sizes {
		b.bit_sizes[i + base_index] = bit_size
	}
	expand_usings(ast_context, b)
}

expand_usings :: proc(ast_context: ^AstContext, b: ^analysis.SymbolStructValueBuilder) {
	base := len(b.names) - 1
	for len(b.unexpanded_usings) > 0 {
		u := pop_front(&b.unexpanded_usings)

		field_expr := b.types[u]
		pkg := get_package_from_node(field_expr.expr_base)
		set_ast_package_set_scoped(ast_context, pkg)


		if field_expr == nil {
			continue
		}

		append(&b.usings, u)

		derived := field_expr.derived
		if param, ok := derived.(^ast.Paren_Expr); ok {
			derived = param.expr.derived
		}

		if ptr, ok := derived.(^ast.Pointer_Type); ok {
			(ptr.elem != nil) or_continue
			derived = ptr.elem.derived
		}

		if ident, ok := derived.(^ast.Ident); ok {
			if v, ok := struct_type_from_identifier(ast_context, ident^); ok {
				write_struct_type(ast_context, b, v, {}, u)
			} else {
				clear(&ast_context.recursion_map)
				if symbol, ok := resolve_type_identifier(ast_context, ident^); ok {
					if v, ok := symbol.value.(analysis.SymbolStructValue); ok {
						write_symbol_struct_value(ast_context, b, v, u)
					} else if v, ok := symbol.value.(analysis.SymbolBitFieldValue); ok {
						write_symbol_bitfield_value(ast_context, b, v, u)
					}
				}
			}
		} else if selector, ok := derived.(^ast.Selector_Expr); ok {
			if symbol, ok := resolve_selector_expression(ast_context, selector); ok {
				if v, ok := symbol.value.(analysis.SymbolStructValue); ok {
					write_symbol_struct_value(ast_context, b, v, u)
				} else if v, ok := symbol.value.(analysis.SymbolBitFieldValue); ok {
					write_symbol_bitfield_value(ast_context, b, v, u)
				}
			}
		} else if v, ok := derived.(^ast.Struct_Type); ok {
			write_struct_type(ast_context, b, v, {}, u)
		} else if v, ok := derived.(^ast.Bit_Field_Type); ok {
			if symbol, ok := resolve_type_expression(ast_context, field_expr); ok {
				if v, ok := symbol.value.(analysis.SymbolBitFieldValue); ok {
					write_symbol_bitfield_value(ast_context, b, v, u)
				}
			}
		}
		delete_key(&ast_context.recursion_map, b.types[u])
	}
}

expand_objc :: proc(ast_context: ^AstContext, b: ^analysis.SymbolStructValueBuilder) {
	symbol := b.symbol
	if .ObjC in symbol.flags {
		pkg := ast_context.symbols.packages[symbol.pkg]

		if obj_struct, ok := pkg.objc_structs[symbol.name]; ok {
			_objc_function: for function, i in obj_struct.functions {
				base := analysis.new_type(ast.Ident, {}, {})
				base.name = obj_struct.pkg

				field := analysis.new_type(ast.Ident, {}, {})
				field.name = function.physical_name

				selector := analysis.new_type(ast.Selector_Expr, {}, {})

				selector.field = field
				selector.expr = base

				//Check if the base functions need to be overridden. Potentially look at some faster approach than a linear loop.
				for name, j in b.names {
					if name == function.logical_name {
						b.names[j] = function.logical_name
						b.types[j] = selector
						b.ranges[j] = obj_struct.ranges[i]
						continue _objc_function
					}
				}

				append(&b.names, function.logical_name)
				append(&b.types, selector)
				append(&b.ranges, obj_struct.ranges[i])
				append(&b.docs, nil)
				append(&b.comments, nil)
				append(&b.from_usings, -1)
			}
		}
	}
}

is_struct_field_using :: proc(v: analysis.SymbolStructValue, index: int) -> bool {
	for i in v.usings {
		if i == index {
			return true
		}
	}
	return false
}

get_proc_arg_count :: proc(v: analysis.SymbolProcedureValue) -> int {
	total := 0
	for proc_arg in v.arg_types {
		for name in proc_arg.names {
			total += 1
		}
	}
	return total
}

// Gets the call argument type at the specified index
get_proc_arg_type_from_index :: proc(value: analysis.SymbolProcedureValue, parameter_index: int) -> (^ast.Field, bool) {
	index := 0
	for arg in value.arg_types {
		// We're in a variadic arg, so return true
		if arg.type != nil {
			if _, ok := arg.type.derived.(^ast.Ellipsis); ok {
				return arg, true
			}
		}
		for name in arg.names {
			if index == parameter_index {
				return arg, true
			}
			index += 1
		}
	}
	return nil, false
}

get_proc_arg_type_from_name :: proc(v: analysis.SymbolProcedureValue, name: string) -> (^ast.Field, bool) {
	for arg in v.arg_types {
		for arg_name in arg.names {
			if ident, ok := arg_name.derived.(^ast.Ident); ok {
				if name == ident.name {
					return arg, true
				}
			}
		}
	}
	return nil, false
}

get_proc_arg_name_from_name :: proc(v: analysis.SymbolProcedureValue, name: string) -> (^ast.Ident, bool) {
	for arg in v.arg_types {
		for arg_name in arg.names {
			if ident, ok := arg_name.derived.(^ast.Ident); ok {
				if name == ident.name {
					return ident, true
				}
			}
		}
	}
	return nil, false
}

new_clone_symbol :: proc(data: analysis.Symbol, allocator := context.allocator) -> ^analysis.Symbol {
	new_symbol := new(analysis.Symbol, allocator)
	new_symbol^ = data
	new_symbol.value = data.value
	return new_symbol
}

free_symbol :: proc(symbol: analysis.Symbol, allocator: mem.Allocator) {
	if symbol.signature != "" &&
	   symbol.signature != "struct" &&
	   symbol.signature != "union" &&
	   symbol.signature != "enum" &&
	   symbol.signature != "bitset" &&
	   symbol.signature != "bit_field" {
		delete(symbol.signature, allocator)
	}

	if symbol.doc != "" {
		delete(symbol.doc, allocator)
	}

	switch v in symbol.value {
	case analysis.SymbolMatrixValue:
		analysis.free_ast(v.expr, allocator)
		analysis.free_ast(v.x, allocator)
		analysis.free_ast(v.y, allocator)
	case analysis.SymbolMultiPointerValue:
		analysis.free_ast(v.expr, allocator)
	case analysis.SymbolProcedureValue:
		analysis.free_ast(v.return_types, allocator)
		analysis.free_ast(v.arg_types, allocator)
	case analysis.SymbolStructValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
		analysis.free_ast(v.types, allocator)
	case analysis.SymbolGenericValue:
		analysis.free_ast(v.expr, allocator)
	case analysis.SymbolProcedureGroupValue:
		analysis.free_ast(v.group, allocator)
	case analysis.SymbolEnumValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
	case analysis.SymbolUnionValue:
		analysis.free_ast(v.types, allocator)
	case analysis.SymbolBitSetValue:
		analysis.free_ast(v.expr, allocator)
	case analysis.SymbolDynamicArrayValue:
		analysis.free_ast(v.expr, allocator)
	case analysis.SymbolFixedArrayValue:
		analysis.free_ast(v.expr, allocator)
		analysis.free_ast(v.len, allocator)
	case analysis.SymbolSliceValue:
		analysis.free_ast(v.expr, allocator)
	case analysis.SymbolBasicValue:
		analysis.free_ast(v.ident, allocator)
	case analysis.SymbolPolyTypeValue:
		analysis.free_ast(v.ident, allocator)
	case analysis.SymbolAggregateValue:
		for symbol in v.symbols {
			free_symbol(symbol, allocator)
		}
	case analysis.SymbolMapValue:
		analysis.free_ast(v.key, allocator)
		analysis.free_ast(v.value, allocator)
	case analysis.SymbolUntypedValue:
		delete(v.tok.text)
	case analysis.SymbolPackageValue:
	case analysis.SymbolBitFieldValue:
		delete(v.names, allocator)
		delete(v.ranges, allocator)
		analysis.free_ast(v.types, allocator)
	}
}

symbol_type_to_completion_kind :: proc(type: analysis.SymbolType) -> CompletionItemKind {
	switch type {
	case .Function:
		return .Function
	case .Field:
		return .Field
	case .Variable:
		return .Variable
	case .Package:
		return .Module
	case .Enum:
		return .Enum
	case .Keyword:
		return .Keyword
	case .EnumMember:
		return .EnumMember
	case .Constant:
		return .Constant
	case .Struct:
		return .Struct
	case .Type_Function:
		return .Function
	case .Union:
		return .Enum
	case .Unresolved:
		return .Text
	case .Type:
		return .Constant
	case:
		return .Text
	}
}

symbol_kind_to_type :: proc(type: analysis.SymbolType) -> SymbolKind {
	#partial switch type {
	case .Function, .Type_Function:
		return .Function
	case .Constant:
		return .Constant
	case .Variable:
		return .Variable
	case .Union:
		return .Enum
	case .Struct:
		return .Struct
	case .Enum:
		return .Enum
	case .Keyword:
		return .Key
	case .Field:
		return .Field
	case .Unresolved:
		return .Constant
	case .Type:
		return .Class
	case:
		return .Null
	}
}

symbol_to_expr :: proc(symbol: analysis.Symbol, file: string) -> ^ast.Expr {

	pos := tokenizer.Pos {
		file = file,
	}

	end := tokenizer.Pos {
		file = file,
	}

	#partial switch v in symbol.value {
	case analysis.SymbolDynamicArrayValue:
		type := analysis.new_type(ast.Dynamic_Array_Type, pos, end)
		type.elem = v.expr
		if .Soa in symbol.flags {
			directive := analysis.new_type(ast.Basic_Directive, pos, end)
			directive.name = "soa"
			type.tag = directive
		}
		return type
	case analysis.SymbolFixedArrayValue:
		type := analysis.new_type(ast.Array_Type, pos, end)
		type.elem = v.expr
		type.len = v.len
		if .Soa in symbol.flags {
			directive := analysis.new_type(ast.Basic_Directive, pos, end)
			directive.name = "soa"
			type.tag = directive
		}
		return type
	case analysis.SymbolMapValue:
		type := analysis.new_type(ast.Map_Type, pos, end)
		type.key = v.key
		type.value = v.value
		return type
	case analysis.SymbolBasicValue:
		return v.ident
	case analysis.SymbolSliceValue:
		type := analysis.new_type(ast.Array_Type, pos, end)
		type.elem = v.expr
		if .Soa in symbol.flags {
			directive := analysis.new_type(ast.Basic_Directive, pos, end)
			directive.name = "soa"
			type.tag = directive
		}
		return type
	case analysis.SymbolStructValue:
		type := analysis.new_type(ast.Struct_Type, pos, end)
		return type
	case analysis.SymbolEnumValue:
		type := analysis.new_type(ast.Enum_Type, pos, end)
		return type
	case analysis.SymbolUnionValue:
		type := analysis.new_type(ast.Union_Type, pos, end)
		return type
	case analysis.SymbolBitSetValue:
		type := analysis.new_type(ast.Bit_Set_Type, pos, end)
		return type
	case analysis.SymbolUntypedValue:
		type := analysis.new_type(ast.Basic_Lit, pos, end)
		type.tok = v.tok
		return type
	case analysis.SymbolMatrixValue:
		type := analysis.new_type(ast.Matrix_Type, pos, end)
		type.row_count = v.x
		type.column_count = v.y
		type.elem = v.expr
		return type
	case analysis.SymbolProcedureValue:
		type := analysis.new_type(ast.Proc_Type, pos, end)
		type.results = analysis.new_type(ast.Field_List, pos, end)
		type.results.list = v.return_types
		type.params = analysis.new_type(ast.Field_List, pos, end)
		type.params.list = v.arg_types
		return type
	case analysis.SymbolBitFieldValue:
		type := analysis.new_type(ast.Bit_Field_Type, pos, end)
		return type
	case analysis.SymbolMultiPointerValue:
		type := analysis.new_type(ast.Multi_Pointer_Type, pos, end)
		type.elem = v.expr
		return type
	case:
		return nil
	}

	return nil
}

// TODO: these will need ranges of the fields as well
construct_struct_field_symbol :: proc(symbol: ^analysis.Symbol, parent_name: string, value: analysis.SymbolStructValue, index: int) {
	using analysis
	symbol.type_pkg = symbol.pkg
	symbol.type_name = symbol.name
	symbol.name = value.names[index]
	symbol.type = .Field
	symbol.parent_name = parent_name
	symbol.doc = get_comment(value.docs[index], context.temp_allocator)
	symbol.comment = get_comment(value.comments[index], context.temp_allocator)
	symbol.range = value.ranges[index]
}

construct_bit_field_field_symbol :: proc(
	symbol: ^analysis.Symbol,
	parent_name: string,
	value: analysis.SymbolBitFieldValue,
	index: int,
) {
	using analysis
	symbol.name = value.names[index]
	symbol.parent_name = parent_name
	symbol.type = .Field
	symbol.doc = get_comment(value.docs[index], context.temp_allocator)
	symbol.comment = get_comment(value.comments[index], context.temp_allocator)
	symbol.signature = get_bit_field_field_signature(value, index)
	symbol.range = value.ranges[index]
}

construct_enum_field_symbol :: proc(symbol: ^analysis.Symbol, value: analysis.SymbolEnumValue, index: int) {
	using analysis
	symbol.type = .Field
	symbol.doc = get_comment(value.docs[index], context.temp_allocator)
	symbol.comment = get_comment(value.comments[index], context.temp_allocator)
	symbol.signature = get_enum_field_signature(value, index)
	symbol.range = value.ranges[index]
}

// Adds name and type information to the symbol when it's for an identifier
construct_ident_symbol_info :: proc(symbol: ^analysis.Symbol, ident: string, document_pkg: string) {
	symbol.type_name = symbol.name
	symbol.type_pkg = symbol.pkg
	symbol.name = ident
	if symbol.type == .Variable || symbol.type == .Constant {
		symbol.pkg = document_pkg
	}

	// If the pkg + name is the same as the type pkg + name, we use the underlying type instead
	// This is used for things like anonymous structs
	if symbol.name == symbol.type_name && symbol.pkg == symbol.type_pkg {
		symbol.type_name = ""
		symbol.type_pkg = ""
	}
}
