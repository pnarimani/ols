#+feature dynamic-literals
package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:strings"

import "src:analysis"
import "src:common"

write_hover_content :: proc(ast_context: ^AstContext, symbol: analysis.Symbol) -> MarkupContent {
	content: MarkupContent
	cat := construct_symbol_information(ast_context, symbol)
	doc := construct_symbol_docs(symbol)

	if cat != "" {
		content.kind = "markdown"
		if doc != "" {
			content.value = fmt.tprintf(DOC_FMT_MARKDOWN, cat, doc)
		} else {
			content.value = fmt.tprintf(DOC_FMT_ODIN, cat)
		}
	} else {
		content.kind = "plaintext"
	}

	return content
}

@(private = "file")
try_hover_keyword_or_directive :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	Hover,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.type_cast != nil &&
	   !position_in_node(position_context.type_cast.type, position_context.position) &&
	   !position_in_node(position_context.type_cast.expr, position_context.position) {
		if str, ok := keywords_docs[position_context.type_cast.tok.text]; ok {
			hover.contents.kind = "markdown"
			hover.contents.value = str
			hover.range = common.get_token_range(position_context.type_cast, ast_context.file.src)
			return hover, true
		}
	}

	if position_context.directive != nil && position_in_node(position_context.directive, position_context.position) {
		if str, ok := directive_docs[position_context.directive.name]; ok {
			hover.contents.kind = "markdown"
			hover.contents.value = str
			hover.range = common.get_token_range(position_context.directive, ast_context.file.src)
			return hover, true
		}
	}

	if position_context.identifier != nil {
		if ident, ok := position_context.identifier.derived.(^ast.Ident); ok {
			if str, ok := keywords_docs[ident.name]; ok {
				hover.contents.kind = "markdown"
				hover.contents.value = str
				hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src)
				return hover, true
			}
		}
	}

	if position_context.implicit_context != nil {
		if str, ok := keywords_docs[position_context.implicit_context.tok.text]; ok {
			hover.contents.kind = "markdown"
			hover.contents.value = str
			hover.range = common.get_token_range(position_context.implicit_context^, ast_context.file.src)
			return hover, true
		}
	}

	return hover, false
}

@(private = "file")
try_hover_enum_field :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	Hover,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.value_decl == nil || len(position_context.value_decl.names) == 0 {
		return hover, false
	}
	if position_context.enum_type == nil {
		return hover, false
	}

	enum_symbol, ok := resolve_type_expression(ast_context, position_context.value_decl.names[0])
	if !ok {
		return hover, false
	}
	v, ok2 := enum_symbol.value.(analysis.SymbolEnumValue)
	if !ok2 {
		return hover, false
	}

	for field in position_context.enum_type.fields {
		if ident, ok := field.derived.(^ast.Ident); ok {
			if position_in_node(ident, position_context.position) {
				for name, i in v.names {
					if name == ident.name {
						construct_enum_field_symbol(&enum_symbol, v, i)
						hover.contents = write_hover_content(ast_context, enum_symbol)
						hover.range = enum_symbol.range
						return hover, true
					}
				}
			}
		} else if value, ok := field.derived.(^ast.Field_Value); ok {
			if position_in_node(value.field, position_context.position) {
				if ident, ok := value.field.derived.(^ast.Ident); ok {
					for name, i in v.names {
						if name == ident.name {
							construct_enum_field_symbol(&enum_symbol, v, i)
							hover.range = enum_symbol.range
							hover.contents = write_hover_content(ast_context, enum_symbol)
						}
					}
				}
				return hover, true
			}
		}
	}

	return hover, false
}

@(private = "file")
try_hover_struct_field :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	Hover,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.struct_type == nil {
		return hover, false
	}

	for field, field_index in position_context.struct_type.fields.list {
		for name, name_index in field.names {
			if !position_in_node(name, position_context.position) {
				continue
			}
			identifier := name.derived.(^ast.Ident) or_continue
			if field.type == nil {
				continue
			}

			symbol := resolve_type_expression(ast_context, field.type) or_continue
			struct_symbol := resolve_type_expression(ast_context, &position_context.struct_type.node) or_continue
			value_decl_symbol := resolve_type_expression(ast_context, position_context.value_decl.names[0]) or_continue
			
			parent_name := get_field_parent_name(value_decl_symbol, struct_symbol)
			value := struct_symbol.value.(analysis.SymbolStructValue) or_continue
			
			construct_struct_field_symbol(&symbol, parent_name, value, field_index + name_index)
			build_documentation(ast_context, &symbol, true)
			hover.range = symbol.range
			hover.contents = write_hover_content(ast_context, symbol)
			return hover, true
		}
	}

	return hover, false
}

@(private = "file")
try_hover_bit_field :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	Hover,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.bit_field_type == nil {
		return hover, false
	}

	for field, i in position_context.bit_field_type.fields {
		if !position_in_node(field.name, position_context.position) {
			continue
		}
		identifier := field.name.derived.(^ast.Ident) or_continue
		if field.type == nil {
			continue
		}

		symbol := resolve_type_expression(ast_context, field.type) or_continue
		bit_field_symbol := resolve_type_expression(ast_context, &position_context.bit_field_type.node) or_continue
		value_decl_symbol := resolve_type_expression(ast_context, position_context.value_decl.names[0]) or_continue
		
		parent_name := get_field_parent_name(value_decl_symbol, bit_field_symbol)
		value := bit_field_symbol.value.(analysis.SymbolBitFieldValue) or_continue
		
		construct_bit_field_field_symbol(&symbol, parent_name, value, i)
		hover.range = symbol.range
		hover.contents = write_hover_content(ast_context, symbol)
		return hover, true
	}

	return hover, false
}

@(private = "file")
try_hover_field_value :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	req_ctx: ^RequestContext,
) -> (
	Hover,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.field_value == nil {
		return hover, false
	}
	if !position_in_node(position_context.field_value.field, position_context.position) {
		return hover, false
	}

	hover.range = common.get_token_range(position_context.field_value.field^, req_ctx.doc_ctx.ast.src)

	if position_context.comp_lit != nil {
		comp_symbol, ok := resolve_comp_literal(ast_context, position_context)
		if !ok {
			return hover, false
		}
		field, ok2 := position_context.field_value.field.derived.(^ast.Ident)
		if !ok2 {
			return hover, false
		}
		
		if !position_in_node(field, position_context.position) {
			return hover, false
		}

		if v, ok := comp_symbol.value.(analysis.SymbolStructValue); ok {
			for name, i in v.names {
				if name == field.name {
					symbol := resolve_type_expression(ast_context, v.types[i]) or_continue
					construct_struct_field_symbol(&symbol, comp_symbol.name, v, i)
					build_documentation(ast_context, &symbol, true)
					hover.contents = write_hover_content(ast_context, symbol)
					return hover, true
				}
			}
		} else if v, ok := comp_symbol.value.(analysis.SymbolBitFieldValue); ok {
			for name, i in v.names {
				if name == field.name {
					symbol := resolve_type_expression(ast_context, v.types[i]) or_continue
					construct_bit_field_field_symbol(&symbol, comp_symbol.name, v, i)
					hover.contents = write_hover_content(ast_context, symbol)
					return hover, true
				}
			}
		}
	}

	if position_context.call != nil {
		symbol, ok := resolve_type_location_proc_param_name(ast_context, position_context)
		if ok {
			build_documentation(ast_context, &symbol, false)
			hover.contents = write_hover_content(ast_context, symbol)
			return hover, true
		}
	}

	return hover, false
}

@(private = "file")
try_hover_selector :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	req_ctx: ^RequestContext,
) -> (
	Hover,
	bool,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.selector == nil || position_context.identifier == nil {
		return hover, false, false
	}
	if position_context.field != position_context.identifier {
		return hover, false, false
	}

	hover.range = common.get_token_range(position_context.identifier^, ast_context.file.src)

	reset_ast_context(ast_context)
	ast_context.current_package = ast_context.document_package

	if base, ok := position_context.selector.derived.(^ast.Ident); ok && position_context.identifier != nil {
		ident := position_context.identifier.derived.(^ast.Ident)^

		if position_in_node(base, position_context.position) {
			if resolved, ok := resolve_type_identifier(ast_context, ident); ok {
				build_documentation(ast_context, &resolved, false)
				resolved.name = ident.name

				if resolved.type == .Variable {
					resolved.pkg = ast_context.document_package
				}

				hover.contents = write_hover_content(ast_context, resolved)
				return hover, true, true
			}
		}
	}

	selector, ok := resolve_type_expression(ast_context, position_context.selector)
	if !ok {
		return hover, false, true
	}

	field: string
	if position_context.field != nil {
		#partial switch v in position_context.field.derived {
		case ^ast.Ident:
			field = v.name
		}
	}

	if v, is_proc := selector.value.(analysis.SymbolProcedureValue); is_proc {
		if len(v.return_types) == 0 || v.return_types[0].type == nil {
			return {}, false, false
		}

		set_ast_package_set_scoped(ast_context, selector.pkg)

		selector, ok = resolve_type_expression(ast_context, v.return_types[0].type)
		if !ok {
			return {}, false, true
		}
	}

	ast_context.current_package = selector.pkg

	#partial switch v in selector.value {
	case analysis.SymbolStructValue:
		for name, i in v.names {
			if name == field {
				symbol := resolve_type_expression(ast_context, v.types[i]) or_continue
				construct_struct_field_symbol(&symbol, selector.name, v, i)
				build_documentation(ast_context, &symbol, true)
				hover.contents = write_hover_content(ast_context, symbol)
				return hover, true, true
			}
		}
	case analysis.SymbolBitFieldValue:
		for name, i in v.names {
			if name == field {
				symbol := resolve_type_expression(ast_context, v.types[i]) or_continue
				construct_bit_field_field_symbol(&symbol, selector.name, v, i)
				hover.contents = write_hover_content(ast_context, symbol)
				return hover, true, true
			}
		}
	case analysis.SymbolPackageValue:
		if position_context.field != nil {
			if ident, ok := position_context.field.derived.(^ast.Ident); ok {
				if position_context.call != nil && ast_context.call == nil {
					if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
						if !position_in_exprs(call.args, position_context.position) {
							ast_context.call = call
						}
					}
				}

				if resolved, ok := resolve_symbol_return(
					ast_context,
					lookup(ident.name, selector.pkg, ast_context.fullpath),
				); ok {
					build_documentation(ast_context, &resolved, false)
					resolved.name = ident.name

					if resolved.type == .Variable {
						resolved.pkg = ast_context.document_package
					}

					hover.contents = write_hover_content(ast_context, resolved)
					return hover, true, true
				}
			}
		}
	case analysis.SymbolEnumValue:
		for name, i in v.names {
			if name == field {
				symbol := analysis.Symbol {
					name      = selector.name,
					pkg       = selector.pkg,
					signature = get_enum_field_signature(v, i),
					type      = .Field,
				}
				hover.contents = write_hover_content(ast_context, symbol)
				return hover, true, true
			}
		}
	case analysis.SymbolSliceValue:
		return get_soa_field_hover(ast_context, selector, v.expr, nil, field)
	case analysis.SymbolDynamicArrayValue:
		if field == "allocator" {
			if symbol, ok := resolve_container_allocator(ast_context, "Raw_Dynamic_Array"); ok {
				hover.contents = write_hover_content(ast_context, symbol)
				return hover, true, true
			}
		}
		return get_soa_field_hover(ast_context, selector, v.expr, nil, field)
	case analysis.SymbolFixedArrayValue:
		return get_soa_field_hover(ast_context, selector, v.expr, v.len, field)
	case analysis.SymbolMapValue:
		if field == "allocator" {
			if symbol, ok := resolve_container_allocator(ast_context, "Raw_Map"); ok {
				hover.contents = write_hover_content(ast_context, symbol)
				return hover, true, true
			}
		}
	}

	return hover, false, false
}

@(private = "file")
try_hover_implicit_selector :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	req_ctx: ^RequestContext,
) -> (
	Hover,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.implicit_selector_expr == nil {
		return hover, false
	}

	implicit_selector := position_context.implicit_selector_expr
	hover.range = common.get_token_range(implicit_selector, req_ctx.doc_ctx.ast.src)

	symbol, ok := resolve_implicit_selector(ast_context, position_context)
	if !ok {
		return hover, false
	}

	#partial switch v in symbol.value {
	case analysis.SymbolEnumValue:
		for name, i in v.names {
			if strings.compare(name, implicit_selector.field.name) == 0 {
				construct_enum_field_symbol(&symbol, v, i)
				hover.contents = write_hover_content(ast_context, symbol)
				return hover, true
			}
		}
	case analysis.SymbolUnionValue:
		for type in v.types {
			enum_symbol := resolve_type_expression(ast_context, type) or_continue
			v := enum_symbol.value.(analysis.SymbolEnumValue) or_continue
			for name, i in v.names {
				if strings.compare(name, implicit_selector.field.name) == 0 {
					construct_enum_field_symbol(&enum_symbol, v, i)
					hover.contents = write_hover_content(ast_context, enum_symbol)
					return hover, true
				}
			}
		}
	case analysis.SymbolBitSetValue:
		enum_symbol, enum_ok := resolve_type_expression(ast_context, v.expr)
		if !enum_ok {
			return hover, false
		}
		enum_value, value_ok := enum_symbol.value.(analysis.SymbolEnumValue)
		if !value_ok {
			return hover, false
		}
		for name, i in enum_value.names {
			if strings.compare(name, implicit_selector.field.name) == 0 {
				construct_enum_field_symbol(&enum_symbol, enum_value, i)
				hover.contents = write_hover_content(ast_context, enum_symbol)
				return hover, true
			}
		}
	}

	return hover, false
}

@(private = "file")
try_hover_identifier :: proc(
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	req_ctx: ^RequestContext,
) -> (
	Hover,
	bool,
) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	if position_context.identifier == nil {
		return hover, false
	}

	reset_ast_context(ast_context)
	ast_context.current_package = ast_context.document_package

	ident := position_context.identifier.derived.(^ast.Ident)^

	if position_context.value_decl != nil {
		ident.pos = position_context.value_decl.end
		ident.end = position_context.value_decl.end
	}

	hover.range = common.get_token_range(position_context.identifier^, req_ctx.doc_ctx.ast.src)

	if position_context.call != nil {
		if call, ok := position_context.call.derived.(^ast.Call_Expr); ok {
			if !position_in_exprs(call.args, position_context.position) {
				ast_context.call = call
			}
		}
	}

	resolved, ok := resolve_type_identifier(ast_context, ident)
	if !ok {
		return hover, false
	}
	construct_ident_symbol_info(&resolved, ident.name, ast_context.document_package)
	build_documentation(ast_context, &resolved, false)
	hover.contents = write_hover_content(ast_context, resolved)
	return hover, true
}

get_hover_information :: proc(req_ctx: ^RequestContext) -> (Hover, bool, bool) {
	hover := Hover {
		contents = {kind = "plaintext"},
	}

	ast_context := make_ast_context(req_ctx)

	position_context, ok := get_document_position_context(req_ctx.doc_ctx, req_ctx.position, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return hover, false, false
	}

	ast_context.position_hint = position_context.hint

	get_globals(req_ctx.doc_ctx.ast, &ast_context)

	if position_context.function != nil {
		get_locals(req_ctx.doc_ctx.ast, position_context.function, &ast_context, &position_context)
	}

	if position_context.import_stmt != nil {
		return {}, false, true
	}

	if hover, ok := try_hover_keyword_or_directive(&ast_context, &position_context); ok {
		return hover, true, true
	}

	if position_context.value_decl != nil && len(position_context.value_decl.names) != 0 {
		if hover, ok := try_hover_enum_field(&ast_context, &position_context); ok {
			return hover, true, true
		}

		if hover, ok := try_hover_struct_field(&ast_context, &position_context); ok {
			return hover, true, true
		}

		if hover, ok := try_hover_bit_field(&ast_context, &position_context); ok {
			return hover, true, true
		}
	}

	if hover, ok := try_hover_field_value(&ast_context, &position_context, req_ctx); ok {
		return hover, true, true
	}

	if hover, ok, done := try_hover_selector(&ast_context, &position_context, req_ctx); done {
		return hover, ok, true
	}

	if hover, ok := try_hover_implicit_selector(&ast_context, &position_context, req_ctx); ok {
		return hover, true, true
	}

	if hover, ok := try_hover_identifier(&ast_context, &position_context, req_ctx); ok {
		return hover, true, true
	}

	return hover, false, true
}

@(private = "file")
get_soa_field_hover :: proc(
	ast_context: ^AstContext,
	selector: analysis.Symbol,
	expr: ^ast.Expr,
	size: ^ast.Expr,
	field: string,
) -> (
	Hover,
	bool,
	bool,
) {
	if .SoaPointer not_in selector.flags && .Soa not_in selector.flags {
		return {}, false, true
	}
	if symbol, ok := resolve_soa_selector_field(ast_context, selector, expr, size, field); ok {
		if selector.name != "" {
			symbol.parent_name = selector.name
		}
		symbol.name = field
		build_documentation(ast_context, &symbol, false)
		hover: Hover
		hover.contents = write_hover_content(ast_context, symbol)
		return hover, true, true
	}
	return {}, false, true
}

@(private = "file")
get_field_parent_name :: proc(value_decl_symbol, symbol: analysis.Symbol) -> string {
	if value_decl_symbol.range != symbol.range {
		return symbol.name
	}
	return value_decl_symbol.name
}
