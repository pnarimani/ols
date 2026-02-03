#+private file
#+feature dynamic-literals

package server

import "core:odin/ast"
import "core:strings"
import "src:documents"

import "src:codeprint"
import "src:common"

EXTRACT_VARIABLE_ACTION_TITLE :: "Extract Variable"
EXTRACT_VARIABLE_ACTION_KIND :: "refactor.extract"
DEFAULT_VARIABLE_NAME :: "extracted"

ExtractVariableContext :: struct {
	doc_ctx:           documents.Document,
	ast_context:       ^AstContext,
	selection_start:   common.AbsolutePosition,
	selection_end:     common.AbsolutePosition,
	containing_proc:   ^ast.Proc_Lit,
	selected_expr:     ^ast.Expr,
	containing_stmt:   ^ast.Stmt,
	stmt_start_pos:    common.Position,
	// Variables that would go out of scope if we extract to before containing_stmt
	out_of_scope_vars: [dynamic]string,
	// Index of the selected expression in the values/rhs array (for multi-value assignments)
	value_index:       int,
}

@(private = "package")
add_extract_variable_action :: proc(
	doc_ctx: documents.Document,
	ast_context: ^AstContext,
	range: common.Range,
	uri: common.FileUri,
	actions: ^[dynamic]CodeAction,
) {
	if !has_valid_selection(range) {
		return
	}

	ctx, ok := create_extract_variable_context(doc_ctx, ast_context, range)
	if !ok {
		return
	}

	// Don't extract simple identifiers or literals - not useful
	if is_trivial_expr(ctx.selected_expr) {
		return
	}

	// Check if the expression uses variables that would go out of scope
	if expr_uses_out_of_scope_vars(&ctx) {
		return
	}

	edit, edit_ok := generate_extract_variable_edit(&ctx, uri, range)
	if !edit_ok {
		return
	}

	append(
		actions,
		CodeAction {
			kind = EXTRACT_VARIABLE_ACTION_KIND,
			isPreferred = false,
			title = EXTRACT_VARIABLE_ACTION_TITLE,
			edit = edit,
		},
	)
}

// Check if the selection range is non-empty
has_valid_selection :: proc(range: common.Range) -> bool {
	return range.start.line != range.end.line || range.start.character != range.end.character
}

// Check if an expression is too trivial to extract (single identifier or literal)
is_trivial_expr :: proc(expr: ^ast.Expr) -> bool {
	if expr == nil {
		return true
	}

	#partial switch _ in expr.derived {
	case ^ast.Ident, ^ast.Basic_Lit:
		return true
	}

	return false
}

// Check if the selected expression uses any variables that would go out of scope
// when extracted to before the containing statement
expr_uses_out_of_scope_vars :: proc(ctx: ^ExtractVariableContext) -> bool {
	if len(ctx.out_of_scope_vars) == 0 {
		return false
	}

	// Collect all identifiers used in the selected expression
	used_idents := collect_identifiers(ctx.selected_expr)
	defer delete(used_idents)

	// Check if any used identifier matches an out-of-scope variable
	for ident in used_idents {
		for var_name in ctx.out_of_scope_vars {
			if ident == var_name {
				return true
			}
		}
	}

	return false
}

// Collect all identifier names from an expression
collect_identifiers :: proc(expr: ^ast.Expr) -> [dynamic]string {
	idents := make([dynamic]string, context.temp_allocator)
	collect_identifiers_recursive(expr, &idents)
	return idents
}

collect_identifiers_recursive :: proc(expr: ^ast.Expr, idents: ^[dynamic]string) {
	if expr == nil {
		return
	}

	#partial switch e in expr.derived {
	case ^ast.Ident:
		append(idents, e.name)

	case ^ast.Binary_Expr:
		collect_identifiers_recursive(e.left, idents)
		collect_identifiers_recursive(e.right, idents)

	case ^ast.Unary_Expr:
		collect_identifiers_recursive(e.expr, idents)

	case ^ast.Paren_Expr:
		collect_identifiers_recursive(e.expr, idents)

	case ^ast.Call_Expr:
		collect_identifiers_recursive(e.expr, idents)
		for arg in e.args {
			collect_identifiers_recursive(arg, idents)
		}

	case ^ast.Index_Expr:
		collect_identifiers_recursive(e.expr, idents)
		collect_identifiers_recursive(e.index, idents)

	case ^ast.Selector_Expr:
		collect_identifiers_recursive(e.expr, idents)
	// Note: we don't collect the selector (field name) as it's not a variable reference

	case ^ast.Ternary_If_Expr:
		collect_identifiers_recursive(e.cond, idents)
		collect_identifiers_recursive(e.x, idents)
		collect_identifiers_recursive(e.y, idents)

	case ^ast.Comp_Lit:
		for elem in e.elems {
			collect_identifiers_recursive(elem, idents)
		}

	case ^ast.Slice_Expr:
		collect_identifiers_recursive(e.expr, idents)
		collect_identifiers_recursive(e.low, idents)
		collect_identifiers_recursive(e.high, idents)

	case ^ast.Deref_Expr:
		collect_identifiers_recursive(e.expr, idents)

	case ^ast.Type_Cast:
		collect_identifiers_recursive(e.expr, idents)

	case ^ast.Auto_Cast:
		collect_identifiers_recursive(e.expr, idents)

	case ^ast.Or_Else_Expr:
		collect_identifiers_recursive(e.x, idents)
		collect_identifiers_recursive(e.y, idents)

	case ^ast.Field_Value:
		// For struct literals like Point{x = a, y = b}, collect the value but not the field name
		collect_identifiers_recursive(e.value, idents)
	}
}

create_extract_variable_context :: proc(
	doc_ctx: documents.Document,
	ast_context: ^AstContext,
	range: common.Range,
) -> (
	ExtractVariableContext,
	bool,
) {
	ctx := ExtractVariableContext {
		doc_ctx           = doc_ctx,
		ast_context       = ast_context,
		out_of_scope_vars = make([dynamic]string),
	}

	start_pos, start_ok := common.get_absolute_position(range.start, doc_ctx.text)
	end_pos, end_ok := common.get_absolute_position(range.end, doc_ctx.text)
	if !start_ok || !end_ok {
		return ctx, false
	}

	ctx.selection_start = start_pos
	ctx.selection_end = end_pos

	// Use shared utility from action_utils.odin
	ctx.containing_proc = find_containing_proc(doc_ctx.ast.decls[:], ctx.selection_start)
	if ctx.containing_proc == nil {
		return ctx, false
	}

	find_selected_expression(&ctx)

	return ctx, ctx.selected_expr != nil
}

// Find the expression matching the selection and its containing statement
find_selected_expression :: proc(ctx: ^ExtractVariableContext) {
	if ctx.containing_proc == nil || ctx.containing_proc.body == nil {
		return
	}

	body, ok := ctx.containing_proc.body.derived.(^ast.Block_Stmt)
	if !ok {
		return
	}

	ctx.selected_expr, ctx.containing_stmt = find_expression_in_stmts(body.stmts[:], ctx)
	if ctx.containing_stmt != nil {
		ctx.stmt_start_pos = common.token_pos_to_position(ctx.containing_stmt.pos, ctx.doc_ctx.ast.src)
	}
}

// Recursively search statements for an expression matching the selection
find_expression_in_stmts :: proc(stmts: []^ast.Stmt, ctx: ^ExtractVariableContext) -> (^ast.Expr, ^ast.Stmt) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		// Skip statements that don't overlap with the selection
		if stmt.end.offset < ctx.selection_start || stmt.pos.offset > ctx.selection_end {
			continue
		}
		if expr, containing := find_expression_in_stmt(stmt, ctx); expr != nil {
			return expr, containing
		}
	}
	return nil, nil
}

// Search for matching expression within a statement
find_expression_in_stmt :: proc(stmt: ^ast.Stmt, ctx: ^ExtractVariableContext) -> (^ast.Expr, ^ast.Stmt) {
	if stmt == nil {
		return nil, nil
	}

	#partial switch s in stmt.derived {
	case ^ast.If_Stmt:
		if s.init != nil {
			if expr, containing := find_expression_in_stmt(s.init, ctx); expr != nil {
				return expr, containing
			}
		}
		if expr := find_matching_expression(s.cond, ctx); expr != nil {
			// Extracting from condition - init vars would be out of scope
			collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
			return expr, stmt
		}
		if s.body != nil {
			if block, ok := s.body.derived.(^ast.Block_Stmt); ok {
				if expr, containing := find_expression_in_stmts(block.stmts[:], ctx); expr != nil {
					// If containing is the if stmt itself, init vars are out of scope
					if containing == stmt {
						collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
					}
					return expr, containing
				}
			}
		}
		if s.else_stmt != nil {
			if expr, containing := find_expression_in_stmt(s.else_stmt, ctx); expr != nil {
				// If containing is the if stmt itself, init vars are out of scope
				if containing == stmt {
					collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
				}
				return expr, containing
			}
		}

	case ^ast.For_Stmt:
		if s.init != nil {
			if expr, containing := find_expression_in_stmt(s.init, ctx); expr != nil {
				return expr, containing
			}
		}
		if expr := find_matching_expression(s.cond, ctx); expr != nil {
			// Extracting from condition - init vars would be out of scope
			collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
			return expr, stmt
		}
		if s.post != nil {
			if expr, containing := find_expression_in_stmt(s.post, ctx); expr != nil {
				// Extracting from post - init vars would be out of scope
				collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
				return expr, containing != nil ? containing : stmt
			}
		}
		if s.body != nil {
			if block, ok := s.body.derived.(^ast.Block_Stmt); ok {
				if expr, containing := find_expression_in_stmts(block.stmts[:], ctx); expr != nil {
					// If containing is the for stmt itself, init vars are out of scope
					if containing == stmt {
						collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
					}
					return expr, containing
				}
			}
		}

	case ^ast.Range_Stmt:
		if expr := find_matching_expression(s.expr, ctx); expr != nil {
			return expr, stmt
		}
		if s.body != nil {
			if block, ok := s.body.derived.(^ast.Block_Stmt); ok {
				if expr, containing := find_expression_in_stmts(block.stmts[:], ctx); expr != nil {
					return expr, containing
				}
			}
		}

	case ^ast.Switch_Stmt:
		if s.init != nil {
			if expr, containing := find_expression_in_stmt(s.init, ctx); expr != nil {
				return expr, containing
			}
		}
		if expr := find_matching_expression(s.cond, ctx); expr != nil {
			// Extracting from condition - init vars would be out of scope
			collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
			return expr, stmt
		}
		if s.body != nil {
			if block, ok := s.body.derived.(^ast.Block_Stmt); ok {
				if expr, containing := find_expression_in_stmts(block.stmts[:], ctx); expr != nil {
					// If containing is the switch stmt itself, init vars are out of scope
					if containing == stmt {
						collect_declared_vars_from_stmt(s.init, &ctx.out_of_scope_vars)
					}
					return expr, containing
				}
			}
		}

	case ^ast.Value_Decl:
		for value, i in s.values {
			if expr := find_matching_expression(value, ctx); expr != nil {
				ctx.value_index = i
				return expr, stmt
			}
		}

	case ^ast.Assign_Stmt:
		for rhs, i in s.rhs {
			if expr := find_matching_expression(rhs, ctx); expr != nil {
				ctx.value_index = i
				return expr, stmt
			}
		}

	case ^ast.Expr_Stmt:
		if expr := find_matching_expression(s.expr, ctx); expr != nil {
			return expr, stmt
		}

	case ^ast.Return_Stmt:
		for result in s.results {
			if expr := find_matching_expression(result, ctx); expr != nil {
				return expr, stmt
			}
		}

	case ^ast.Block_Stmt:
		if expr, containing := find_expression_in_stmts(s.stmts[:], ctx); expr != nil {
			return expr, containing
		}

	case ^ast.Case_Clause:
		if expr, containing := find_expression_in_stmts(s.body[:], ctx); expr != nil {
			return expr, containing
		}
	}

	return nil, nil
}

// Collect variable names declared in a statement (typically an init statement)
collect_declared_vars_from_stmt :: proc(stmt: ^ast.Stmt, vars: ^[dynamic]string) {
	if stmt == nil {
		return
	}

	#partial switch s in stmt.derived {
	case ^ast.Value_Decl:
		for name in s.names {
			if name != nil {
				if ident, ok := name.derived.(^ast.Ident); ok {
					append(vars, ident.name)
				}
			}
		}
	case ^ast.Assign_Stmt:
		// For assignments like `i := 0`, collect lhs identifiers
		for lhs in s.lhs {
			if lhs != nil {
				if ident, ok := lhs.derived.(^ast.Ident); ok {
					append(vars, ident.name)
				}
			}
		}
	}
}

// Check if an expression exactly matches the selection, or search inside it.
// If no exact match is found, returns the smallest expression containing the entire selection.
find_matching_expression :: proc(expr: ^ast.Expr, ctx: ^ExtractVariableContext) -> ^ast.Expr {
	if expr == nil {
		return nil
	}

	// Exact match
	if expr.pos.offset == ctx.selection_start && expr.end.offset == ctx.selection_end {
		return expr
	}

	// Selection not within this expression
	if expr.end.offset < ctx.selection_start || expr.pos.offset > ctx.selection_end {
		return nil
	}

	// Search inside compound expressions for exact match first
	#partial switch e in expr.derived {
	case ^ast.Binary_Expr:
		if result := find_matching_expression(e.left, ctx); result != nil {
			return result
		}
		if result := find_matching_expression(e.right, ctx); result != nil {
			return result
		}

	case ^ast.Unary_Expr:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}

	case ^ast.Paren_Expr:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}

	case ^ast.Call_Expr:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}
		for arg in e.args {
			if result := find_matching_expression(arg, ctx); result != nil {
				return result
			}
		}

	case ^ast.Index_Expr:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}
		if result := find_matching_expression(e.index, ctx); result != nil {
			return result
		}

	case ^ast.Selector_Expr:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}

	case ^ast.Ternary_If_Expr:
		if result := find_matching_expression(e.cond, ctx); result != nil {
			return result
		}
		if result := find_matching_expression(e.x, ctx); result != nil {
			return result
		}
		if result := find_matching_expression(e.y, ctx); result != nil {
			return result
		}

	case ^ast.Comp_Lit:
		for elem in e.elems {
			if result := find_matching_expression(elem, ctx); result != nil {
				return result
			}
		}

	case ^ast.Slice_Expr:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}
		if result := find_matching_expression(e.low, ctx); result != nil {
			return result
		}
		if result := find_matching_expression(e.high, ctx); result != nil {
			return result
		}

	case ^ast.Deref_Expr:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}

	case ^ast.Type_Cast:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}

	case ^ast.Auto_Cast:
		if result := find_matching_expression(e.expr, ctx); result != nil {
			return result
		}

	case ^ast.Or_Else_Expr:
		if result := find_matching_expression(e.x, ctx); result != nil {
			return result
		}
		if result := find_matching_expression(e.y, ctx); result != nil {
			return result
		}
	}

	// No exact match found inside; if this expression fully contains the selection,
	// return it as the smallest containing expression (allows partial/semantic extraction)
	if expr.pos.offset <= ctx.selection_start && expr.end.offset >= ctx.selection_end {
		return expr
	}

	return nil
}

generate_extract_variable_edit :: proc(
	ctx: ^ExtractVariableContext,
	uri: FileUri,
	selection_range: common.Range,
) -> (
	WorkspaceEdit,
	bool,
) {
	src := ctx.doc_ctx.ast.src

	// Get the original expression text from source
	expr_text := string(src[ctx.selection_start:ctx.selection_end])

	// Get the indentation of the containing statement
	indent := get_line_indentation(src, int(ctx.containing_stmt.pos.offset))

	// Check if we need an explicit type annotation (for auto_cast)
	type_annotation := get_auto_cast_type_annotation(ctx)

	// Build the variable declaration
	var_decl: string
	if type_annotation != "" {
		// "<indent>extracted: <type> = <expr>\n<indent>"
		var_decl = strings.concatenate(
			{indent, DEFAULT_VARIABLE_NAME, ": ", type_annotation, " = ", expr_text, "\n", indent},
			context.temp_allocator,
		)
	} else {
		// "<indent>extracted := <expr>\n<indent>"
		var_decl = strings.concatenate(
			{indent, DEFAULT_VARIABLE_NAME, " := ", expr_text, "\n", indent},
			context.temp_allocator,
		)
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)

	// Replace the statement's leading indentation with the variable declaration + restored indent
	// This effectively inserts a new line while maintaining proper indentation
	replace_range := common.Range {
		start = common.Position{line = ctx.stmt_start_pos.line, character = 0},
		end = common.Position{line = ctx.stmt_start_pos.line, character = ctx.stmt_start_pos.character},
	}
	append(&textEdits, TextEdit{range = replace_range, newText = var_decl})

	// Replace the original expression with the variable name
	append(&textEdits, TextEdit{range = selection_range, newText = DEFAULT_VARIABLE_NAME})

	return make_workspace_edit(uri, textEdits[:]), true
}

// Get type annotation for auto_cast expressions by looking at the target type
get_auto_cast_type_annotation :: proc(ctx: ^ExtractVariableContext) -> string {
	// Check if the selected expression is an auto_cast
	if ctx.selected_expr == nil {
		return ""
	}

	_, is_auto_cast := ctx.selected_expr.derived.(^ast.Auto_Cast)
	if !is_auto_cast {
		return ""
	}

	// Get the target type from the containing statement
	#partial switch s in ctx.containing_stmt.derived {
	case ^ast.Value_Decl:
		// For value declarations like `y: i32 = auto_cast x`, get the type annotation
		if s.type != nil {
			return codeprint.node_to_string(s.type)
		}

	case ^ast.Assign_Stmt:
		// For assignments like `y = auto_cast x`, look up the type of the LHS
		if ctx.value_index < len(s.lhs) {
			lhs := s.lhs[ctx.value_index]
			if lhs != nil {
				return resolve_lhs_type(ctx, lhs)
			}
		}
	}

	return ""
}

// Resolve the type of a left-hand side expression (typically an identifier)
resolve_lhs_type :: proc(ctx: ^ExtractVariableContext, lhs: ^ast.Expr) -> string {
	if lhs == nil || ctx.ast_context == nil {
		return ""
	}

	// For simple identifiers, look up in locals first
	if ident, ok := lhs.derived.(^ast.Ident); ok {
		if local, found := get_local(ctx.ast_context^, ident^); found {
			if local.type_expr != nil {
				return codeprint.node_to_string(local.type_expr)
			}
		}
	}

	// Fall back to general type expression resolution
	symbol, ok := resolve_type_expression(ctx.ast_context, lhs)
	if !ok || symbol.type_expr == nil {
		return ""
	}

	return codeprint.node_to_string(symbol.type_expr)
}
