#+private file
#+feature dynamic-literals

package server

import "core:odin/ast"
import "core:slice"
import "core:strings"

import "src:common"

INLINE_VARIABLE_ACTION_TITLE :: "Inline Variable"
INLINE_VARIABLE_ACTION_KIND :: "refactor.inline"

InlineVariableContext :: struct {
	doc_ctx:          DocumentContext,
	ast_context:      ^AstContext,
	position:         common.AbsolutePosition,
	// The variable declaration containing the variable to inline
	var_decl:         ^ast.Value_Decl,
	// The name of the variable to inline
	var_name:         string,
	// The index of the variable in the names array (for multi-variable declarations)
	var_index:        int,
	// The expression the variable is initialized with
	init_expr:        ^ast.Expr,
	// All usages of the variable (identifiers that reference it)
	all_usages:       [dynamic]^ast.Ident,
	// The containing procedure
	containing_proc:  ^ast.Proc_Lit,
	// If cursor is on a usage site, this is the specific usage to inline (nil = inline all from declaration)
	target_usage:     ^ast.Ident,
}

@(private = "package")
add_inline_variable_action :: proc(
	doc_ctx: DocumentContext,
	ast_context: ^AstContext,
	range: common.Range,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	// Only available for point selections (cursor), not range selections
	if range.start.line != range.end.line || range.start.character != range.end.character {
		return
	}

	ctx, ok := create_inline_variable_context(doc_ctx, ast_context, range.start)
	if !ok {
		return
	}
	defer destroy_inline_variable_context(&ctx)

	// Must have an initialization expression
	if ctx.init_expr == nil {
		return
	}

	// Must have at least one usage
	if len(ctx.all_usages) == 0 {
		return
	}

	// Variable must not be reassigned after initialization
	if is_variable_reassigned(&ctx) {
		return
	}

	edit, edit_ok := generate_inline_variable_edit(&ctx, uri)
	if !edit_ok {
		return
	}

	append(
		actions,
		CodeAction {
			kind = INLINE_VARIABLE_ACTION_KIND,
			isPreferred = false,
			title = INLINE_VARIABLE_ACTION_TITLE,
			edit = edit,
		},
	)
}

create_inline_variable_context :: proc(
	doc_ctx: DocumentContext,
	ast_context: ^AstContext,
	position: common.Position,
) -> (
	InlineVariableContext,
	bool,
) {
	ctx := InlineVariableContext {
		doc_ctx     = doc_ctx,
		ast_context = ast_context,
		all_usages  = make([dynamic]^ast.Ident, context.temp_allocator),
	}

	abs_pos, ok := common.get_absolute_position(position, doc_ctx.text)
	if !ok {
		return ctx, false
	}
	ctx.position = abs_pos

	// Find the containing procedure
	ctx.containing_proc = find_containing_proc(doc_ctx.ast.decls[:], abs_pos)
	if ctx.containing_proc == nil {
		return ctx, false
	}

	// First, try to find a variable declaration at the cursor position
	ctx.var_decl, ctx.var_name, ctx.var_index, ctx.init_expr = find_variable_decl_at_position(
		ctx.containing_proc.body,
		abs_pos,
	)

	if ctx.var_decl != nil && ctx.var_name != "" && ctx.init_expr != nil {
		// Cursor is on declaration - inline all usages
		// Only support single-variable declarations for now
		if len(ctx.var_decl.names) != 1 {
			return ctx, false
		}

		// Find all usages of this variable in the containing procedure
		find_all_variable_usages(ctx.containing_proc.body, ctx.var_name, ctx.var_decl, &ctx.all_usages)
		return ctx, true
	}

	// Try to find if cursor is on a variable usage
	ctx.target_usage = find_ident_at_position(ctx.containing_proc.body, abs_pos)
	if ctx.target_usage == nil {
		return ctx, false
	}

	// Find the declaration for this identifier
	ctx.var_name = ctx.target_usage.name
	ctx.var_decl, ctx.var_index, ctx.init_expr = find_variable_decl_by_name(
		ctx.containing_proc.body,
		ctx.var_name,
		ctx.target_usage,
	)

	if ctx.var_decl == nil || ctx.init_expr == nil {
		return ctx, false
	}

	// Only support single-variable declarations for now
	if len(ctx.var_decl.names) != 1 {
		return ctx, false
	}

	// For usage-site inlining, we still need all usages to check if this is the only one
	// (to decide whether to delete the declaration)
	find_all_variable_usages(ctx.containing_proc.body, ctx.var_name, ctx.var_decl, &ctx.all_usages)

	return ctx, true
}

destroy_inline_variable_context :: proc(ctx: ^InlineVariableContext) {
	delete(ctx.all_usages)
}

// Find a variable declaration at the given position
// Returns the declaration, variable name, index in names array, and initialization expression
find_variable_decl_at_position :: proc(
	stmt: ^ast.Stmt,
	position: common.AbsolutePosition,
) -> (^ast.Value_Decl, string, int, ^ast.Expr) {
	if stmt == nil {
		return nil, "", 0, nil
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			if decl, name, idx, expr := find_variable_decl_at_position(inner, position); decl != nil {
				return decl, name, idx, expr
			}
		}
	case ^ast.Value_Decl:
		// Check if cursor is on one of the variable names
		for name, i in s.names {
			if position_in_node(name, position) {
				if ident, ok := name.derived.(^ast.Ident); ok {
					// Make sure there's a corresponding value
					if i < len(s.values) {
						// Don't inline procedure declarations
						if _, is_proc := s.values[i].derived.(^ast.Proc_Lit); is_proc {
							return nil, "", 0, nil
						}
						return s, ident.name, i, s.values[i]
					}
				}
			}
		}
	case ^ast.If_Stmt:
		if s.body != nil {
			if decl, name, idx, expr := find_variable_decl_at_position(s.body, position); decl != nil {
				return decl, name, idx, expr
			}
		}
		if s.else_stmt != nil {
			if decl, name, idx, expr := find_variable_decl_at_position(s.else_stmt, position); decl != nil {
				return decl, name, idx, expr
			}
		}
	case ^ast.For_Stmt:
		if s.body != nil {
			if decl, name, idx, expr := find_variable_decl_at_position(s.body, position); decl != nil {
				return decl, name, idx, expr
			}
		}
	case ^ast.Range_Stmt:
		if s.body != nil {
			if decl, name, idx, expr := find_variable_decl_at_position(s.body, position); decl != nil {
				return decl, name, idx, expr
			}
		}
	case ^ast.Switch_Stmt:
		if s.body != nil {
			if decl, name, idx, expr := find_variable_decl_at_position(s.body, position); decl != nil {
				return decl, name, idx, expr
			}
		}
	case ^ast.Type_Switch_Stmt:
		if s.body != nil {
			if decl, name, idx, expr := find_variable_decl_at_position(s.body, position); decl != nil {
				return decl, name, idx, expr
			}
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			if decl, name, idx, expr := find_variable_decl_at_position(inner, position); decl != nil {
				return decl, name, idx, expr
			}
		}
	}

	return nil, "", 0, nil
}

// Find an identifier at the given position (for usage site detection)
find_ident_at_position :: proc(stmt: ^ast.Stmt, position: common.AbsolutePosition) -> ^ast.Ident {
	if stmt == nil {
		return nil
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			if result := find_ident_at_position(inner, position); result != nil {
				return result
			}
		}
	case ^ast.Value_Decl:
		// Search in values (not names - those are handled by find_variable_decl_at_position)
		for value in s.values {
			if result := find_ident_in_expr(value, position); result != nil {
				return result
			}
		}
	case ^ast.Assign_Stmt:
		for lhs in s.lhs {
			if result := find_ident_in_expr(lhs, position); result != nil {
				return result
			}
		}
		for rhs in s.rhs {
			if result := find_ident_in_expr(rhs, position); result != nil {
				return result
			}
		}
	case ^ast.Expr_Stmt:
		if result := find_ident_in_expr(s.expr, position); result != nil {
			return result
		}
	case ^ast.Return_Stmt:
		for result in s.results {
			if r := find_ident_in_expr(result, position); r != nil {
				return r
			}
		}
	case ^ast.If_Stmt:
		if s.cond != nil {
			if result := find_ident_in_expr(s.cond, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_ident_at_position(s.body, position); result != nil {
				return result
			}
		}
		if s.else_stmt != nil {
			if result := find_ident_at_position(s.else_stmt, position); result != nil {
				return result
			}
		}
	case ^ast.For_Stmt:
		if s.cond != nil {
			if result := find_ident_in_expr(s.cond, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_ident_at_position(s.body, position); result != nil {
				return result
			}
		}
	case ^ast.Range_Stmt:
		if s.expr != nil {
			if result := find_ident_in_expr(s.expr, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_ident_at_position(s.body, position); result != nil {
				return result
			}
		}
	case ^ast.Switch_Stmt:
		if s.cond != nil {
			if result := find_ident_in_expr(s.cond, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_ident_at_position(s.body, position); result != nil {
				return result
			}
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			if result := find_ident_at_position(inner, position); result != nil {
				return result
			}
		}
	}

	return nil
}

find_ident_in_expr :: proc(expr: ^ast.Expr, position: common.AbsolutePosition) -> ^ast.Ident {
	if expr == nil {
		return nil
	}

	if !position_in_node(expr, position) {
		return nil
	}

	#partial switch e in expr.derived {
	case ^ast.Ident:
		return e
	case ^ast.Binary_Expr:
		if result := find_ident_in_expr(e.left, position); result != nil {
			return result
		}
		return find_ident_in_expr(e.right, position)
	case ^ast.Unary_Expr:
		return find_ident_in_expr(e.expr, position)
	case ^ast.Paren_Expr:
		return find_ident_in_expr(e.expr, position)
	case ^ast.Call_Expr:
		if result := find_ident_in_expr(e.expr, position); result != nil {
			return result
		}
		for arg in e.args {
			if result := find_ident_in_expr(arg, position); result != nil {
				return result
			}
		}
	case ^ast.Index_Expr:
		if result := find_ident_in_expr(e.expr, position); result != nil {
			return result
		}
		return find_ident_in_expr(e.index, position)
	case ^ast.Selector_Expr:
		// Only check the base expression, not the field
		return find_ident_in_expr(e.expr, position)
	case ^ast.Slice_Expr:
		if result := find_ident_in_expr(e.expr, position); result != nil {
			return result
		}
		if e.low != nil {
			if result := find_ident_in_expr(e.low, position); result != nil {
				return result
			}
		}
		if e.high != nil {
			if result := find_ident_in_expr(e.high, position); result != nil {
				return result
			}
		}
	case ^ast.Ternary_If_Expr:
		if result := find_ident_in_expr(e.cond, position); result != nil {
			return result
		}
		if result := find_ident_in_expr(e.x, position); result != nil {
			return result
		}
		return find_ident_in_expr(e.y, position)
	case ^ast.Comp_Lit:
		for elem in e.elems {
			if result := find_ident_in_expr(elem, position); result != nil {
				return result
			}
		}
	case ^ast.Field_Value:
		return find_ident_in_expr(e.value, position)
	case ^ast.Deref_Expr:
		return find_ident_in_expr(e.expr, position)
	case ^ast.Type_Cast:
		return find_ident_in_expr(e.expr, position)
	case ^ast.Auto_Cast:
		return find_ident_in_expr(e.expr, position)
	case ^ast.Or_Else_Expr:
		if result := find_ident_in_expr(e.x, position); result != nil {
			return result
		}
		return find_ident_in_expr(e.y, position)
	case ^ast.Or_Return_Expr:
		return find_ident_in_expr(e.expr, position)
	}

	return nil
}

// Find a variable declaration by name, searching backwards from the usage position
find_variable_decl_by_name :: proc(
	stmt: ^ast.Stmt,
	var_name: string,
	usage: ^ast.Ident,
) -> (^ast.Value_Decl, int, ^ast.Expr) {
	if stmt == nil {
		return nil, 0, nil
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		// Search statements that come before the usage
		for inner in s.stmts {
			// Stop if we've passed the usage
			if inner.pos.offset > usage.pos.offset {
				break
			}
			if decl, idx, expr := find_variable_decl_by_name(inner, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
	case ^ast.Value_Decl:
		// Check if this declares our variable
		for name, i in s.names {
			if ident, ok := name.derived.(^ast.Ident); ok {
				if ident.name == var_name && i < len(s.values) {
					// Don't inline procedure declarations
					if _, is_proc := s.values[i].derived.(^ast.Proc_Lit); is_proc {
						return nil, 0, nil
					}
					return s, i, s.values[i]
				}
			}
		}
	case ^ast.If_Stmt:
		if s.body != nil {
			if decl, idx, expr := find_variable_decl_by_name(s.body, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
		if s.else_stmt != nil {
			if decl, idx, expr := find_variable_decl_by_name(s.else_stmt, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
	case ^ast.For_Stmt:
		if s.body != nil {
			if decl, idx, expr := find_variable_decl_by_name(s.body, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
	case ^ast.Range_Stmt:
		if s.body != nil {
			if decl, idx, expr := find_variable_decl_by_name(s.body, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
	case ^ast.Switch_Stmt:
		if s.body != nil {
			if decl, idx, expr := find_variable_decl_by_name(s.body, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
	case ^ast.Type_Switch_Stmt:
		if s.body != nil {
			if decl, idx, expr := find_variable_decl_by_name(s.body, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			if inner.pos.offset > usage.pos.offset {
				break
			}
			if decl, idx, expr := find_variable_decl_by_name(inner, var_name, usage); decl != nil {
				return decl, idx, expr
			}
		}
	}

	return nil, 0, nil
}

// Find all usages of a variable in a statement tree
// Excludes the declaration itself
find_all_variable_usages :: proc(
	stmt: ^ast.Stmt,
	var_name: string,
	var_decl: ^ast.Value_Decl,
	usages: ^[dynamic]^ast.Ident,
) {
	if stmt == nil {
		return
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			find_all_variable_usages(inner, var_name, var_decl, usages)
		}
	case ^ast.Value_Decl:
		// Skip the declaration's own names, but search in its values
		// (for cases like x := y where y is the variable we're looking for)
		if s != var_decl {
			for value in s.values {
				find_usages_in_expr(value, var_name, usages)
			}
		}
	case ^ast.Assign_Stmt:
		// Check both sides of assignment
		for lhs in s.lhs {
			find_usages_in_expr(lhs, var_name, usages)
		}
		for rhs in s.rhs {
			find_usages_in_expr(rhs, var_name, usages)
		}
	case ^ast.Expr_Stmt:
		find_usages_in_expr(s.expr, var_name, usages)
	case ^ast.Return_Stmt:
		for result in s.results {
			find_usages_in_expr(result, var_name, usages)
		}
	case ^ast.If_Stmt:
		if s.init != nil {
			find_all_variable_usages(s.init, var_name, var_decl, usages)
		}
		if s.cond != nil {
			find_usages_in_expr(s.cond, var_name, usages)
		}
		if s.body != nil {
			find_all_variable_usages(s.body, var_name, var_decl, usages)
		}
		if s.else_stmt != nil {
			find_all_variable_usages(s.else_stmt, var_name, var_decl, usages)
		}
	case ^ast.For_Stmt:
		if s.init != nil {
			find_all_variable_usages(s.init, var_name, var_decl, usages)
		}
		if s.cond != nil {
			find_usages_in_expr(s.cond, var_name, usages)
		}
		if s.post != nil {
			find_all_variable_usages(s.post, var_name, var_decl, usages)
		}
		if s.body != nil {
			find_all_variable_usages(s.body, var_name, var_decl, usages)
		}
	case ^ast.Range_Stmt:
		if s.expr != nil {
			find_usages_in_expr(s.expr, var_name, usages)
		}
		if s.body != nil {
			find_all_variable_usages(s.body, var_name, var_decl, usages)
		}
	case ^ast.Switch_Stmt:
		if s.init != nil {
			find_all_variable_usages(s.init, var_name, var_decl, usages)
		}
		if s.cond != nil {
			find_usages_in_expr(s.cond, var_name, usages)
		}
		if s.body != nil {
			find_all_variable_usages(s.body, var_name, var_decl, usages)
		}
	case ^ast.Type_Switch_Stmt:
		if s.tag != nil {
			find_all_variable_usages(s.tag, var_name, var_decl, usages)
		}
		if s.body != nil {
			find_all_variable_usages(s.body, var_name, var_decl, usages)
		}
	case ^ast.Case_Clause:
		for expr in s.list {
			find_usages_in_expr(expr, var_name, usages)
		}
		for inner in s.body {
			find_all_variable_usages(inner, var_name, var_decl, usages)
		}
	case ^ast.Defer_Stmt:
		if s.stmt != nil {
			find_all_variable_usages(s.stmt, var_name, var_decl, usages)
		}
	}
}

// Find usages of a variable in an expression
find_usages_in_expr :: proc(expr: ^ast.Expr, var_name: string, usages: ^[dynamic]^ast.Ident) {
	if expr == nil {
		return
	}

	#partial switch e in expr.derived {
	case ^ast.Ident:
		if e.name == var_name {
			append(usages, e)
		}
	case ^ast.Binary_Expr:
		find_usages_in_expr(e.left, var_name, usages)
		find_usages_in_expr(e.right, var_name, usages)
	case ^ast.Unary_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
	case ^ast.Paren_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
	case ^ast.Call_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
		for arg in e.args {
			find_usages_in_expr(arg, var_name, usages)
		}
	case ^ast.Index_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
		find_usages_in_expr(e.index, var_name, usages)
	case ^ast.Selector_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
		// Don't recurse into field - it's not a variable reference
	case ^ast.Slice_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
		if e.low != nil {
			find_usages_in_expr(e.low, var_name, usages)
		}
		if e.high != nil {
			find_usages_in_expr(e.high, var_name, usages)
		}
	case ^ast.Ternary_If_Expr:
		find_usages_in_expr(e.cond, var_name, usages)
		find_usages_in_expr(e.x, var_name, usages)
		find_usages_in_expr(e.y, var_name, usages)
	case ^ast.Comp_Lit:
		for elem in e.elems {
			find_usages_in_expr(elem, var_name, usages)
		}
	case ^ast.Field_Value:
		find_usages_in_expr(e.value, var_name, usages)
	case ^ast.Deref_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
	case ^ast.Type_Cast:
		find_usages_in_expr(e.expr, var_name, usages)
	case ^ast.Auto_Cast:
		find_usages_in_expr(e.expr, var_name, usages)
	case ^ast.Or_Else_Expr:
		find_usages_in_expr(e.x, var_name, usages)
		find_usages_in_expr(e.y, var_name, usages)
	case ^ast.Or_Return_Expr:
		find_usages_in_expr(e.expr, var_name, usages)
	case ^ast.Proc_Lit:
		// Don't search inside nested procedures - different scope
	}
}

// Check if a variable is reassigned after its declaration
is_variable_reassigned :: proc(ctx: ^InlineVariableContext) -> bool {
	if ctx.containing_proc == nil || ctx.containing_proc.body == nil {
		return false
	}
	return check_reassignment_in_stmt(ctx.containing_proc.body, ctx.var_name, ctx.var_decl)
}

check_reassignment_in_stmt :: proc(stmt: ^ast.Stmt, var_name: string, var_decl: ^ast.Value_Decl) -> bool {
	if stmt == nil {
		return false
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			if check_reassignment_in_stmt(inner, var_name, var_decl) {
				return true
			}
		}
	case ^ast.Assign_Stmt:
		// Check if any LHS is our variable
		for lhs in s.lhs {
			if ident, ok := lhs.derived.(^ast.Ident); ok {
				if ident.name == var_name {
					return true
				}
			}
		}
		// Also check compound assignments in RHS for self-referencing patterns
		// (but the LHS check above should catch most cases)
	case ^ast.If_Stmt:
		if s.init != nil && check_reassignment_in_stmt(s.init, var_name, var_decl) {
			return true
		}
		if s.body != nil && check_reassignment_in_stmt(s.body, var_name, var_decl) {
			return true
		}
		if s.else_stmt != nil && check_reassignment_in_stmt(s.else_stmt, var_name, var_decl) {
			return true
		}
	case ^ast.For_Stmt:
		if s.init != nil && check_reassignment_in_stmt(s.init, var_name, var_decl) {
			return true
		}
		if s.post != nil && check_reassignment_in_stmt(s.post, var_name, var_decl) {
			return true
		}
		if s.body != nil && check_reassignment_in_stmt(s.body, var_name, var_decl) {
			return true
		}
	case ^ast.Range_Stmt:
		// Check if the variable is the iteration variable
		for val in s.vals {
			if val != nil {
				if ident, ok := val.derived.(^ast.Ident); ok {
					if ident.name == var_name {
						return true
					}
				}
			}
		}
		if s.body != nil && check_reassignment_in_stmt(s.body, var_name, var_decl) {
			return true
		}
	case ^ast.Switch_Stmt:
		if s.init != nil && check_reassignment_in_stmt(s.init, var_name, var_decl) {
			return true
		}
		if s.body != nil && check_reassignment_in_stmt(s.body, var_name, var_decl) {
			return true
		}
	case ^ast.Type_Switch_Stmt:
		if s.tag != nil && check_reassignment_in_stmt(s.tag, var_name, var_decl) {
			return true
		}
		if s.body != nil && check_reassignment_in_stmt(s.body, var_name, var_decl) {
			return true
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			if check_reassignment_in_stmt(inner, var_name, var_decl) {
				return true
			}
		}
	case ^ast.Defer_Stmt:
		if s.stmt != nil && check_reassignment_in_stmt(s.stmt, var_name, var_decl) {
			return true
		}
	}

	return false
}

// Generate the workspace edit for inlining the variable
generate_inline_variable_edit :: proc(ctx: ^InlineVariableContext, uri: string) -> (WorkspaceEdit, bool) {
	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	src := ctx.doc_ctx.ast.src

	// Get the initialization expression text
	init_text := string(src[ctx.init_expr.pos.offset:ctx.init_expr.end.offset])

	// Determine if we need to wrap the expression in parentheses for safety
	needs_parens := expr_needs_parentheses(ctx.init_expr)

	if ctx.target_usage != nil {
		// Single usage inlining - only replace the target usage
		usage_range := common.get_token_range(ctx.target_usage, src)
		replacement := init_text
		if needs_parens && usage_needs_parentheses(ctx, ctx.target_usage) {
			replacement = strings.concatenate({"(", init_text, ")"}, context.temp_allocator)
		}
		append(&textEdits, TextEdit{range = usage_range, newText = replacement})

		// If this was the only usage, delete the declaration
		if len(ctx.all_usages) == 1 {
			delete_edit := generate_variable_delete_edit(ctx)
			append(&textEdits, delete_edit)
		}
	} else {
		// Inline all usages (cursor was on declaration)
		// Sort usages by reverse position so edits don't invalidate each other
		slice.sort_by(ctx.all_usages[:], proc(a, b: ^ast.Ident) -> bool {
			return a.pos.offset > b.pos.offset
		})

		// Replace each usage with the initialization expression
		for usage in ctx.all_usages {
			usage_range := common.get_token_range(usage, src)
			replacement := init_text
			if needs_parens && usage_needs_parentheses(ctx, usage) {
				replacement = strings.concatenate({"(", init_text, ")"}, context.temp_allocator)
			}
			append(&textEdits, TextEdit{range = usage_range, newText = replacement})
		}

		// Delete the variable declaration
		delete_edit := generate_variable_delete_edit(ctx)
		append(&textEdits, delete_edit)
	}

	return make_workspace_edit(uri, textEdits[:]), true
}

// Check if an expression should be wrapped in parentheses when inlined
// This is needed for binary expressions, ternary expressions, etc.
expr_needs_parentheses :: proc(expr: ^ast.Expr) -> bool {
	if expr == nil {
		return false
	}

	#partial switch _ in expr.derived {
	case ^ast.Binary_Expr:
		return true
	case ^ast.Ternary_If_Expr:
		return true
	case ^ast.Ternary_When_Expr:
		return true
	case ^ast.Or_Else_Expr:
		return true
	}

	return false
}

// Check if a usage context requires parentheses
// (e.g., when the usage is part of a binary expression with higher precedence)
usage_needs_parentheses :: proc(ctx: ^InlineVariableContext, usage: ^ast.Ident) -> bool {
	// For now, use a simple heuristic: if the init expression needs parens,
	// we add them unless the usage is in a simple context (standalone statement, function arg)
	
	// Find the parent expression of this usage
	parent := find_parent_expr(ctx.containing_proc.body, usage)
	if parent == nil {
		return false
	}

	#partial switch _ in parent.derived {
	case ^ast.Binary_Expr:
		return true
	case ^ast.Index_Expr:
		return true
	case ^ast.Selector_Expr:
		return true
	case ^ast.Unary_Expr:
		return true
	}

	return false
}

// Find the parent expression of an identifier
find_parent_expr :: proc(stmt: ^ast.Stmt, target: ^ast.Ident) -> ^ast.Expr {
	if stmt == nil {
		return nil
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			if result := find_parent_expr(inner, target); result != nil {
				return result
			}
		}
	case ^ast.Value_Decl:
		for value in s.values {
			if result := find_parent_expr_in_expr(value, target); result != nil {
				return result
			}
		}
	case ^ast.Assign_Stmt:
		for lhs in s.lhs {
			if result := find_parent_expr_in_expr(lhs, target); result != nil {
				return result
			}
		}
		for rhs in s.rhs {
			if result := find_parent_expr_in_expr(rhs, target); result != nil {
				return result
			}
		}
	case ^ast.Expr_Stmt:
		if result := find_parent_expr_in_expr(s.expr, target); result != nil {
			return result
		}
	case ^ast.Return_Stmt:
		for result in s.results {
			if r := find_parent_expr_in_expr(result, target); r != nil {
				return r
			}
		}
	case ^ast.If_Stmt:
		if s.cond != nil {
			if result := find_parent_expr_in_expr(s.cond, target); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_parent_expr(s.body, target); result != nil {
				return result
			}
		}
		if s.else_stmt != nil {
			if result := find_parent_expr(s.else_stmt, target); result != nil {
				return result
			}
		}
	case ^ast.For_Stmt:
		if s.cond != nil {
			if result := find_parent_expr_in_expr(s.cond, target); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_parent_expr(s.body, target); result != nil {
				return result
			}
		}
	case ^ast.Switch_Stmt:
		if s.cond != nil {
			if result := find_parent_expr_in_expr(s.cond, target); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_parent_expr(s.body, target); result != nil {
				return result
			}
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			if result := find_parent_expr(inner, target); result != nil {
				return result
			}
		}
	}

	return nil
}

find_parent_expr_in_expr :: proc(expr: ^ast.Expr, target: ^ast.Ident) -> ^ast.Expr {
	if expr == nil {
		return nil
	}

	#partial switch e in expr.derived {
	case ^ast.Ident:
		// This is the target itself, parent is above
		return nil
	case ^ast.Binary_Expr:
		if is_target_ident(e.left, target) || is_target_ident(e.right, target) {
			return expr
		}
		if result := find_parent_expr_in_expr(e.left, target); result != nil {
			return result
		}
		return find_parent_expr_in_expr(e.right, target)
	case ^ast.Unary_Expr:
		if is_target_ident(e.expr, target) {
			return expr
		}
		return find_parent_expr_in_expr(e.expr, target)
	case ^ast.Paren_Expr:
		if is_target_ident(e.expr, target) {
			return nil // Parentheses don't count as needing more parens
		}
		return find_parent_expr_in_expr(e.expr, target)
	case ^ast.Call_Expr:
		if is_target_ident(e.expr, target) {
			return expr
		}
		for arg in e.args {
			if is_target_ident(arg, target) {
				return nil // Function arguments don't need extra parens
			}
			if result := find_parent_expr_in_expr(arg, target); result != nil {
				return result
			}
		}
		return find_parent_expr_in_expr(e.expr, target)
	case ^ast.Index_Expr:
		if is_target_ident(e.expr, target) {
			return expr
		}
		if is_target_ident(e.index, target) {
			return nil // Index doesn't need parens
		}
		if result := find_parent_expr_in_expr(e.expr, target); result != nil {
			return result
		}
		return find_parent_expr_in_expr(e.index, target)
	case ^ast.Selector_Expr:
		if is_target_ident(e.expr, target) {
			return expr
		}
		return find_parent_expr_in_expr(e.expr, target)
	case ^ast.Slice_Expr:
		if is_target_ident(e.expr, target) {
			return expr
		}
		if result := find_parent_expr_in_expr(e.expr, target); result != nil {
			return result
		}
		if e.low != nil {
			if result := find_parent_expr_in_expr(e.low, target); result != nil {
				return result
			}
		}
		if e.high != nil {
			if result := find_parent_expr_in_expr(e.high, target); result != nil {
				return result
			}
		}
	case ^ast.Ternary_If_Expr:
		if is_target_ident(e.cond, target) || is_target_ident(e.x, target) || is_target_ident(e.y, target) {
			return nil // Ternary parts are self-contained
		}
		if result := find_parent_expr_in_expr(e.cond, target); result != nil {
			return result
		}
		if result := find_parent_expr_in_expr(e.x, target); result != nil {
			return result
		}
		return find_parent_expr_in_expr(e.y, target)
	}

	return nil
}

is_target_ident :: proc(expr: ^ast.Expr, target: ^ast.Ident) -> bool {
	if expr == nil {
		return false
	}
	if ident, ok := expr.derived.(^ast.Ident); ok {
		return ident == target
	}
	return false
}

// Generate the edit to delete the variable declaration
generate_variable_delete_edit :: proc(ctx: ^InlineVariableContext) -> TextEdit {
	src := ctx.doc_ctx.ast.src

	// Delete the entire line containing the declaration
	decl_range := common.get_token_range(ctx.var_decl, src)
	
	// Start from the beginning of the line (character 0)
	decl_range.start.character = 0

	// Extend to include the newline after if present
	end_offset, _ := common.get_absolute_position(decl_range.end, ctx.doc_ctx.text)
	if end_offset < len(src) && src[end_offset] == '\n' {
		// Move end position to the start of the next line
		decl_range.end.line += 1
		decl_range.end.character = 0
	}

	return TextEdit{range = decl_range, newText = ""}
}
