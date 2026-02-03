#+private file
#+feature dynamic-literals

package server

import "src:documents"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:slice"
import "core:strings"

import "src:common"

INLINE_PROC_ACTION_TITLE :: "Inline Proc"
INLINE_PROC_ACTION_KIND :: "refactor.inline"

InlineProcContext :: struct {
	doc_ctx:          ^documents.Document,
	ast_context:      ^AstContext,
	position:         common.AbsolutePosition,
	// The call expression if cursor is on a procedure call
	call_expr:        ^ast.Call_Expr,
	// The procedure declaration if cursor is on a procedure definition
	proc_decl:        ^ast.Value_Decl,
	proc_lit:         ^ast.Proc_Lit,
	proc_name:        string,
	// All calls to the procedure (used when inlining from definition)
	all_calls:        [dynamic]^ast.Call_Expr,
}

@(private = "package")
add_inline_proc_action :: proc(
	doc_ctx: ^documents.Document,
	ast_context: ^AstContext,
	range: common.Range,
	uri: common.FileUri,
	actions: ^[dynamic]CodeAction,
) {
	// Only available for point selections (cursor), not range selections
	if range.start.line != range.end.line || range.start.character != range.end.character {
		return
	}

	ctx, ok := create_inline_proc_context(doc_ctx, ast_context, range.start)
	if !ok {
		return
	}
	defer destroy_inline_proc_context(&ctx)

	// Check if we can inline (procedure must have a body)
	if ctx.proc_lit == nil || ctx.proc_lit.body == nil {
		return
	}

	// Procedures with multiple return statements cannot be easily inlined
	if has_multiple_returns(ctx.proc_lit) {
		return
	}

	// For single call inlining, check if the body is simple enough
	if ctx.call_expr != nil && len(ctx.all_calls) == 0 {
		if !can_inline_body_as_expression(&ctx) {
			return
		}
	}

	edit, edit_ok := generate_inline_edit(&ctx, uri)
	if !edit_ok {
		return
	}

	append(
		actions,
		CodeAction {
			kind = INLINE_PROC_ACTION_KIND,
			isPreferred = false,
			title = INLINE_PROC_ACTION_TITLE,
			edit = edit,
		},
	)
}

create_inline_proc_context :: proc(
	doc_ctx: ^documents.Document,
	ast_context: ^AstContext,
	position: common.Position,
) -> (
	InlineProcContext,
	bool,
) {
	ctx := InlineProcContext {
		doc_ctx     = doc_ctx,
		ast_context = ast_context,
		all_calls   = make([dynamic]^ast.Call_Expr, context.temp_allocator),
	}

	abs_pos, ok := common.get_absolute_position(position, doc_ctx.text)
	if !ok {
		return ctx, false
	}
	ctx.position = abs_pos

	// First try to find if we're on a call expression
	ctx.call_expr = find_call_at_position(doc_ctx.syntaxTree.decls[:], abs_pos)

	if ctx.call_expr != nil {
		proc_name := get_call_proc_name(ctx.call_expr)
		if proc_name == "" {
			return ctx, false
		}
		ctx.proc_name = proc_name
		ctx.proc_decl, ctx.proc_lit = find_proc_definition(doc_ctx, ast_context, proc_name)
		if ctx.proc_lit == nil {
			return ctx, false
		}
		return ctx, true
	}

	// Try to find if we're on a procedure definition
	ctx.proc_decl, ctx.proc_lit, ctx.proc_name = find_proc_decl_at_position(doc_ctx.syntaxTree.decls[:], abs_pos)

	if ctx.proc_decl != nil && ctx.proc_lit != nil && ctx.proc_name != "" {
		// Find all calls to this procedure in the file
		find_all_calls_to_proc(doc_ctx.syntaxTree.decls[:], ctx.proc_name, &ctx.all_calls)
		return ctx, len(ctx.all_calls) > 0
	}

	return ctx, false
}

destroy_inline_proc_context :: proc(ctx: ^InlineProcContext) {
	delete(ctx.all_calls)
}

// Find a call expression at the given position
find_call_at_position :: proc(stmts: []^ast.Stmt, position: common.AbsolutePosition) -> ^ast.Call_Expr {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if result := find_call_in_stmt(stmt, position); result != nil {
			return result
		}
	}
	return nil
}

find_call_in_stmt :: proc(stmt: ^ast.Stmt, position: common.AbsolutePosition) -> ^ast.Call_Expr {
	if stmt == nil || !position_in_node(stmt, position) {
		return nil
	}

	#partial switch s in stmt.derived {
	case ^ast.Value_Decl:
		for value in s.values {
			if result := find_call_in_expr(value, position); result != nil {
				return result
			}
		}
	case ^ast.Assign_Stmt:
		for rhs in s.rhs {
			if result := find_call_in_expr(rhs, position); result != nil {
				return result
			}
		}
	case ^ast.Expr_Stmt:
		return find_call_in_expr(s.expr, position)
	case ^ast.Return_Stmt:
		for result in s.results {
			if r := find_call_in_expr(result, position); r != nil {
				return r
			}
		}
	case ^ast.If_Stmt:
		if s.cond != nil {
			if result := find_call_in_expr(s.cond, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_call_in_stmt(s.body, position); result != nil {
				return result
			}
		}
		if s.else_stmt != nil {
			if result := find_call_in_stmt(s.else_stmt, position); result != nil {
				return result
			}
		}
	case ^ast.For_Stmt:
		if s.cond != nil {
			if result := find_call_in_expr(s.cond, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_call_in_stmt(s.body, position); result != nil {
				return result
			}
		}
	case ^ast.Range_Stmt:
		if s.expr != nil {
			if result := find_call_in_expr(s.expr, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_call_in_stmt(s.body, position); result != nil {
				return result
			}
		}
	case ^ast.Block_Stmt:
		return find_call_at_position(s.stmts[:], position)
	case ^ast.Switch_Stmt:
		if s.cond != nil {
			if result := find_call_in_expr(s.cond, position); result != nil {
				return result
			}
		}
		if s.body != nil {
			if result := find_call_in_stmt(s.body, position); result != nil {
				return result
			}
		}
	case ^ast.Case_Clause:
		return find_call_at_position(s.body[:], position)
	}

	return nil
}

find_call_in_expr :: proc(expr: ^ast.Expr, position: common.AbsolutePosition) -> ^ast.Call_Expr {
	if expr == nil {
		return nil
	}

	// Check if position is within this expression
	if position < int(expr.pos.offset) || position > int(expr.end.offset) {
		return nil
	}

	#partial switch e in expr.derived {
	case ^ast.Call_Expr:
		// Check if position is on the call itself (function name)
		if e.expr != nil && position >= int(e.expr.pos.offset) && position <= int(e.expr.end.offset) {
			return e
		}
		// Also check arguments
		for arg in e.args {
			if result := find_call_in_expr(arg, position); result != nil {
				return result
			}
		}
		// If position is in call but not in args, return this call
		return e
	case ^ast.Binary_Expr:
		if result := find_call_in_expr(e.left, position); result != nil {
			return result
		}
		return find_call_in_expr(e.right, position)
	case ^ast.Unary_Expr:
		return find_call_in_expr(e.expr, position)
	case ^ast.Paren_Expr:
		return find_call_in_expr(e.expr, position)
	case ^ast.Index_Expr:
		if result := find_call_in_expr(e.expr, position); result != nil {
			return result
		}
		return find_call_in_expr(e.index, position)
	case ^ast.Selector_Expr:
		return find_call_in_expr(e.expr, position)
	case ^ast.Ternary_If_Expr:
		if result := find_call_in_expr(e.cond, position); result != nil {
			return result
		}
		if result := find_call_in_expr(e.x, position); result != nil {
			return result
		}
		return find_call_in_expr(e.y, position)
	case ^ast.Proc_Lit:
		// Search inside procedure bodies for calls
		if e.body != nil {
			if result := find_call_in_stmt(e.body, position); result != nil {
				return result
			}
		}
		return nil
	}

	return nil
}

// Get the name of the procedure being called
get_call_proc_name :: proc(call: ^ast.Call_Expr) -> string {
	if call == nil || call.expr == nil {
		return ""
	}

	#partial switch e in call.expr.derived {
	case ^ast.Ident:
		return e.name
	case ^ast.Selector_Expr:
		// For method calls like pkg.func(), get just the func name
		if field, ok := e.field.derived.(^ast.Ident); ok {
			return field.name
		}
	}

	return ""
}

// Find a procedure definition by name in the current document
find_proc_definition :: proc(
	doc_ctx: ^documents.Document,
	ast_context: ^AstContext,
	name: string,
) -> (^ast.Value_Decl, ^ast.Proc_Lit) {
	for stmt in doc_ctx.syntaxTree.decls {
		if decl, proc_lit, found := get_proc_from_decl(stmt, name); found {
			return decl, proc_lit
		}
	}
	return nil, nil
}

get_proc_from_decl :: proc(stmt: ^ast.Stmt, name: string) -> (^ast.Value_Decl, ^ast.Proc_Lit, bool) {
	if stmt == nil {
		return nil, nil, false
	}

	#partial switch s in stmt.derived {
	case ^ast.Value_Decl:
		for decl_name, i in s.names {
			if ident, ok := decl_name.derived.(^ast.Ident); ok {
				if ident.name == name && i < len(s.values) {
					if proc_lit, ok := s.values[i].derived.(^ast.Proc_Lit); ok {
						return s, proc_lit, true
					}
				}
			}
		}
	}

	return nil, nil, false
}

// Find a procedure declaration at a given position
find_proc_decl_at_position :: proc(
	stmts: []^ast.Stmt,
	position: common.AbsolutePosition,
) -> (^ast.Value_Decl, ^ast.Proc_Lit, string) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if !position_in_node(stmt, position) {
			continue
		}

		#partial switch s in stmt.derived {
		case ^ast.Value_Decl:
			for name, i in s.names {
				if ident, ok := name.derived.(^ast.Ident); ok {
					// Check if cursor is on the procedure name
					// Use direct offset comparison since name is an Expr not Node
					if position >= int(name.pos.offset) && position <= int(name.end.offset) && i < len(s.values) {
						if proc_lit, ok := s.values[i].derived.(^ast.Proc_Lit); ok {
							return s, proc_lit, ident.name
						}
					}
				}
			}
		}
	}

	return nil, nil, ""
}

// Find all calls to a procedure in the file
find_all_calls_to_proc :: proc(stmts: []^ast.Stmt, proc_name: string, calls: ^[dynamic]^ast.Call_Expr) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		find_calls_in_stmt(stmt, proc_name, calls)
	}
}

find_calls_in_stmt :: proc(stmt: ^ast.Stmt, proc_name: string, calls: ^[dynamic]^ast.Call_Expr) {
	if stmt == nil {
		return
	}

	#partial switch s in stmt.derived {
	case ^ast.Value_Decl:
		for value in s.values {
			// For procedure literals, search inside their body
			if proc_lit, is_proc := value.derived.(^ast.Proc_Lit); is_proc {
				if proc_lit.body != nil {
					find_calls_in_stmt(proc_lit.body, proc_name, calls)
				}
				continue
			}
			find_calls_in_expr(value, proc_name, calls)
		}
	case ^ast.Assign_Stmt:
		for rhs in s.rhs {
			find_calls_in_expr(rhs, proc_name, calls)
		}
	case ^ast.Expr_Stmt:
		find_calls_in_expr(s.expr, proc_name, calls)
	case ^ast.Return_Stmt:
		for result in s.results {
			find_calls_in_expr(result, proc_name, calls)
		}
	case ^ast.If_Stmt:
		if s.init != nil {
			find_calls_in_stmt(s.init, proc_name, calls)
		}
		if s.cond != nil {
			find_calls_in_expr(s.cond, proc_name, calls)
		}
		if s.body != nil {
			find_calls_in_stmt(s.body, proc_name, calls)
		}
		if s.else_stmt != nil {
			find_calls_in_stmt(s.else_stmt, proc_name, calls)
		}
	case ^ast.For_Stmt:
		if s.init != nil {
			find_calls_in_stmt(s.init, proc_name, calls)
		}
		if s.cond != nil {
			find_calls_in_expr(s.cond, proc_name, calls)
		}
		if s.post != nil {
			find_calls_in_stmt(s.post, proc_name, calls)
		}
		if s.body != nil {
			find_calls_in_stmt(s.body, proc_name, calls)
		}
	case ^ast.Range_Stmt:
		if s.expr != nil {
			find_calls_in_expr(s.expr, proc_name, calls)
		}
		if s.body != nil {
			find_calls_in_stmt(s.body, proc_name, calls)
		}
	case ^ast.Block_Stmt:
		find_all_calls_to_proc(s.stmts[:], proc_name, calls)
	case ^ast.Switch_Stmt:
		if s.init != nil {
			find_calls_in_stmt(s.init, proc_name, calls)
		}
		if s.cond != nil {
			find_calls_in_expr(s.cond, proc_name, calls)
		}
		if s.body != nil {
			find_calls_in_stmt(s.body, proc_name, calls)
		}
	case ^ast.Type_Switch_Stmt:
		if s.tag != nil {
			find_calls_in_stmt(s.tag, proc_name, calls)
		}
		if s.body != nil {
			find_calls_in_stmt(s.body, proc_name, calls)
		}
	case ^ast.Case_Clause:
		find_all_calls_to_proc(s.body[:], proc_name, calls)
	case ^ast.Defer_Stmt:
		if s.stmt != nil {
			find_calls_in_stmt(s.stmt, proc_name, calls)
		}
	}
}

find_calls_in_expr :: proc(expr: ^ast.Expr, proc_name: string, calls: ^[dynamic]^ast.Call_Expr) {
	if expr == nil {
		return
	}

	#partial switch e in expr.derived {
	case ^ast.Call_Expr:
		// Check if this call is to our procedure
		call_name := get_call_proc_name(e)
		if call_name == proc_name {
			append(calls, e)
		}
		// Also check arguments for nested calls
		find_calls_in_expr(e.expr, proc_name, calls)
		for arg in e.args {
			find_calls_in_expr(arg, proc_name, calls)
		}
	case ^ast.Binary_Expr:
		find_calls_in_expr(e.left, proc_name, calls)
		find_calls_in_expr(e.right, proc_name, calls)
	case ^ast.Unary_Expr:
		find_calls_in_expr(e.expr, proc_name, calls)
	case ^ast.Paren_Expr:
		find_calls_in_expr(e.expr, proc_name, calls)
	case ^ast.Index_Expr:
		find_calls_in_expr(e.expr, proc_name, calls)
		find_calls_in_expr(e.index, proc_name, calls)
	case ^ast.Selector_Expr:
		find_calls_in_expr(e.expr, proc_name, calls)
	case ^ast.Slice_Expr:
		find_calls_in_expr(e.expr, proc_name, calls)
		if e.low != nil {
			find_calls_in_expr(e.low, proc_name, calls)
		}
		if e.high != nil {
			find_calls_in_expr(e.high, proc_name, calls)
		}
	case ^ast.Ternary_If_Expr:
		find_calls_in_expr(e.cond, proc_name, calls)
		find_calls_in_expr(e.x, proc_name, calls)
		find_calls_in_expr(e.y, proc_name, calls)
	case ^ast.Comp_Lit:
		for elem in e.elems {
			find_calls_in_expr(elem, proc_name, calls)
		}
	case ^ast.Field_Value:
		find_calls_in_expr(e.value, proc_name, calls)
	case ^ast.Proc_Lit:
		// Search inside nested procedure bodies
		if e.body != nil {
			find_calls_in_stmt(e.body, proc_name, calls)
		}
	}
}

// Check if a procedure has multiple return statements
has_multiple_returns :: proc(proc_lit: ^ast.Proc_Lit) -> bool {
	if proc_lit == nil || proc_lit.body == nil {
		return false
	}

	count := 0
	count_returns_in_stmt(proc_lit.body, &count)
	return count > 1
}

count_returns_in_stmt :: proc(stmt: ^ast.Stmt, count: ^int) {
	if stmt == nil {
		return
	}

	#partial switch s in stmt.derived {
	case ^ast.Return_Stmt:
		count^ += 1
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			count_returns_in_stmt(inner, count)
		}
	case ^ast.If_Stmt:
		if s.body != nil {
			count_returns_in_stmt(s.body, count)
		}
		if s.else_stmt != nil {
			count_returns_in_stmt(s.else_stmt, count)
		}
	case ^ast.For_Stmt:
		if s.body != nil {
			count_returns_in_stmt(s.body, count)
		}
	case ^ast.Range_Stmt:
		if s.body != nil {
			count_returns_in_stmt(s.body, count)
		}
	case ^ast.Switch_Stmt:
		if s.body != nil {
			count_returns_in_stmt(s.body, count)
		}
	case ^ast.Type_Switch_Stmt:
		if s.body != nil {
			count_returns_in_stmt(s.body, count)
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			count_returns_in_stmt(inner, count)
		}
	}
}

// Check if a procedure has defer statements
has_defer_statements :: proc(proc_lit: ^ast.Proc_Lit) -> bool {
	if proc_lit == nil || proc_lit.body == nil {
		return false
	}
	return check_defer_in_stmt(proc_lit.body)
}

check_defer_in_stmt :: proc(stmt: ^ast.Stmt) -> bool {
	if stmt == nil {
		return false
	}

	#partial switch s in stmt.derived {
	case ^ast.Defer_Stmt:
		return true
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			if check_defer_in_stmt(inner) {
				return true
			}
		}
	case ^ast.If_Stmt:
		if s.body != nil && check_defer_in_stmt(s.body) {
			return true
		}
		if s.else_stmt != nil && check_defer_in_stmt(s.else_stmt) {
			return true
		}
	case ^ast.For_Stmt:
		if s.body != nil && check_defer_in_stmt(s.body) {
			return true
		}
	case ^ast.Range_Stmt:
		if s.body != nil && check_defer_in_stmt(s.body) {
			return true
		}
	case ^ast.Switch_Stmt:
		if s.body != nil && check_defer_in_stmt(s.body) {
			return true
		}
	case ^ast.Type_Switch_Stmt:
		if s.body != nil && check_defer_in_stmt(s.body) {
			return true
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			if check_defer_in_stmt(inner) {
				return true
			}
		}
	}

	return false
}

// Check if a block has top-level defer statements (direct children only)
has_top_level_defer :: proc(body: ^ast.Block_Stmt) -> bool {
	if body == nil {
		return false
	}
	
	for stmt in body.stmts {
		if stmt == nil {
			continue
		}
		#partial switch _ in stmt.derived {
		case ^ast.Defer_Stmt:
			return true
		}
	}
	return false
}

// Check if a procedure body can be inlined
// Multi-statement bodies are supported
can_inline_body_as_expression :: proc(ctx: ^InlineProcContext) -> bool {
	if ctx.proc_lit == nil || ctx.proc_lit.body == nil {
		return false
	}

	body, ok := ctx.proc_lit.body.derived.(^ast.Block_Stmt)
	if !ok {
		return false
	}

	// Empty body is OK for void procedures
	if len(body.stmts) == 0 {
		return true
	}

	// Multi-statement bodies are supported
	return true
}

// Generate the edit for inlining
generate_inline_edit :: proc(ctx: ^InlineProcContext, uri: FileUri) -> (WorkspaceEdit, bool) {
	textEdits := make([dynamic]TextEdit, context.temp_allocator)

	if ctx.call_expr != nil && len(ctx.all_calls) == 0 {
		// Inline single call
		edit, ok := generate_single_inline_edit(ctx, ctx.call_expr)
		if !ok {
			return {}, false
		}
		append(&textEdits, edit)
	} else if len(ctx.all_calls) > 0 {
		// Inline all calls and delete the procedure
		// Sort calls by reverse position so edits don't invalidate each other
		slice.sort_by(ctx.all_calls[:], proc(a, b: ^ast.Call_Expr) -> bool {
			return a.pos.offset > b.pos.offset
		})

		for call in ctx.all_calls {
			edit, ok := generate_single_inline_edit(ctx, call)
			if !ok {
				return {}, false
			}
			append(&textEdits, edit)
		}

		// Delete the procedure definition
		delete_edit := generate_proc_delete_edit(ctx)
		append(&textEdits, delete_edit)
	} else {
		return {}, false
	}

	return make_workspace_edit(uri, textEdits[:]), true
}

// Generate the inline edit for a single call
generate_single_inline_edit :: proc(ctx: ^InlineProcContext, call: ^ast.Call_Expr) -> (TextEdit, bool) {
	if ctx.proc_lit == nil || ctx.proc_lit.body == nil {
		return {}, false
	}

	src := ctx.doc_ctx.syntaxTree.src

	// Build parameter name to argument mapping
	param_to_arg := make(map[string]string, context.temp_allocator)

	if proc_type, ok := ctx.proc_lit.type.derived.(^ast.Proc_Type); ok {
		if proc_type.params != nil {
			arg_idx := 0
			for field in proc_type.params.list {
				for name in field.names {
					if ident, ok := name.derived.(^ast.Ident); ok {
						if arg_idx < len(call.args) {
							// Get the argument text
							arg_text := string(src[call.args[arg_idx].pos.offset:call.args[arg_idx].end.offset])
							param_to_arg[ident.name] = arg_text
						}
						arg_idx += 1
					}
				}
			}
		}
	}

	// Find the containing statement for this call to determine context
	containing_stmt := find_containing_stmt_for_call(ctx.doc_ctx.syntaxTree.decls[:], call)

	body, body_ok := ctx.proc_lit.body.derived.(^ast.Block_Stmt)
	if !body_ok {
		return {}, false
	}

	// Check if this is a simple single-return body
	is_simple := len(body.stmts) == 1
	if is_simple {
		if _, is_return := body.stmts[0].derived.(^ast.Return_Stmt); !is_return {
			is_simple = false
		}
	}

	// For simple bodies, just replace the call
	if is_simple || is_standalone_call(containing_stmt, call) {
		inlined_code := generate_inlined_body(ctx, param_to_arg, containing_stmt, call, nil)
		call_range := common.get_token_range(call, src)
		return TextEdit{range = call_range, newText = inlined_code}, true
	}

	// For multi-statement bodies in expression context, we need to replace the entire statement
	// and extract the statements before the assignment/usage
	inlined_code := generate_multi_stmt_inline(ctx, param_to_arg, containing_stmt, call)
	stmt_range := common.get_token_range(containing_stmt, src)
	return TextEdit{range = stmt_range, newText = inlined_code}, true
}

// Find the statement that contains a call expression
find_containing_stmt_for_call :: proc(stmts: []^ast.Stmt, call: ^ast.Call_Expr) -> ^ast.Stmt {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if !position_in_node(stmt, int(call.pos.offset)) {
			continue
		}
		if result := find_stmt_containing_call(stmt, call); result != nil {
			return result
		}
	}
	return nil
}

find_stmt_containing_call :: proc(stmt: ^ast.Stmt, call: ^ast.Call_Expr) -> ^ast.Stmt {
	if stmt == nil {
		return nil
	}

	#partial switch s in stmt.derived {
	case ^ast.Value_Decl:
		for value in s.values {
			// If the value is a proc literal, search inside it
			if proc_lit, is_proc := value.derived.(^ast.Proc_Lit); is_proc {
				if proc_lit.body != nil {
					if result := find_stmt_containing_call(proc_lit.body, call); result != nil {
						return result
					}
				}
				continue
			}
			if expr_contains_call(value, call) {
				return stmt
			}
		}
	case ^ast.Assign_Stmt:
		for rhs in s.rhs {
			if expr_contains_call(rhs, call) {
				return stmt
			}
		}
	case ^ast.Expr_Stmt:
		if expr_contains_call(s.expr, call) {
			return stmt
		}
	case ^ast.Return_Stmt:
		for result in s.results {
			if expr_contains_call(result, call) {
				return stmt
			}
		}
	case ^ast.If_Stmt:
		if s.cond != nil && expr_contains_call(s.cond, call) {
			return stmt
		}
		if s.body != nil {
			if result := find_stmt_containing_call(s.body, call); result != nil {
				return result
			}
		}
		if s.else_stmt != nil {
			if result := find_stmt_containing_call(s.else_stmt, call); result != nil {
				return result
			}
		}
	case ^ast.For_Stmt:
		if s.cond != nil && expr_contains_call(s.cond, call) {
			return stmt
		}
		if s.body != nil {
			if result := find_stmt_containing_call(s.body, call); result != nil {
				return result
			}
		}
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			if result := find_stmt_containing_call(inner, call); result != nil {
				return result
			}
		}
	case ^ast.Switch_Stmt:
		if s.cond != nil && expr_contains_call(s.cond, call) {
			return stmt
		}
		if s.body != nil {
			if result := find_stmt_containing_call(s.body, call); result != nil {
				return result
			}
		}
	case ^ast.Case_Clause:
		for inner in s.body {
			if result := find_stmt_containing_call(inner, call); result != nil {
				return result
			}
		}
	}

	return nil
}

expr_contains_call :: proc(expr: ^ast.Expr, call: ^ast.Call_Expr) -> bool {
	if expr == nil {
		return false
	}
	return expr == call || (expr.pos.offset <= call.pos.offset && expr.end.offset >= call.end.offset)
}

// Generate the inlined procedure body for simple cases
generate_inlined_body :: proc(
	ctx: ^InlineProcContext,
	param_to_arg: map[string]string,
	containing_stmt: ^ast.Stmt,
	call: ^ast.Call_Expr,
	local_renames: ^map[string]string,
) -> string {
	if ctx.proc_lit == nil || ctx.proc_lit.body == nil {
		return ""
	}

	body, ok := ctx.proc_lit.body.derived.(^ast.Block_Stmt)
	if !ok {
		return ""
	}

	src := ctx.doc_ctx.syntaxTree.src

	// Determine if this is a simple expression context or a statement context
	is_expr_context := !is_standalone_call(containing_stmt, call)

	// If it's an expression context and the procedure has a single return with a single expression,
	// we can inline as just the expression
	if is_expr_context {
		if return_expr := get_single_return_expr(body); return_expr != nil {
			// Simple case: procedure is just "return expr"
			return substitute_params(string(src[return_expr.pos.offset:return_expr.end.offset]), param_to_arg, local_renames)
		}
	}

	// For statement context with multi-statement body
	sb := strings.builder_make(context.temp_allocator)
	
	// Get indentation for continuation lines
	indent := get_stmt_indentation(containing_stmt, src)
	
	// Check if we need to wrap in a block due to defer
	needs_block := has_top_level_defer(body)
	
	if needs_block {
		strings.write_string(&sb, "{\n")
	}

	first_stmt := true
	for stmt in body.stmts {
		#partial switch s in stmt.derived {
		case ^ast.Return_Stmt:
			// Skip return statements in statement context
			continue
		case:
			if !first_stmt {
				strings.write_byte(&sb, '\n')
				strings.write_string(&sb, indent)
				if needs_block {
					strings.write_string(&sb, "    ")
				}
			} else if needs_block {
				// First statement inside block needs indent + block indent
				strings.write_string(&sb, indent)
				strings.write_string(&sb, "    ")
			}
			stmt_text := string(src[stmt.pos.offset:stmt.end.offset])
			substituted := substitute_params(stmt_text, param_to_arg, local_renames)
			if needs_block {
				// Reindent multi-line statements (like nested blocks) with extra indent
				substituted = reindent_text(substituted, indent, "    ")
			}
			strings.write_string(&sb, substituted)
			first_stmt = false
		}
	}
	
	if needs_block {
		strings.write_byte(&sb, '\n')
		strings.write_string(&sb, indent)
		strings.write_string(&sb, "}")
	}

	return strings.to_string(sb)
}
// Generate inlined code for multi-statement bodies in expression context
// This replaces the entire containing statement
generate_multi_stmt_inline :: proc(
	ctx: ^InlineProcContext,
	param_to_arg: map[string]string,
	containing_stmt: ^ast.Stmt,
	call: ^ast.Call_Expr,
) -> string {
	if ctx.proc_lit == nil || ctx.proc_lit.body == nil {
		return ""
	}

	body, ok := ctx.proc_lit.body.derived.(^ast.Block_Stmt)
	if !ok {
		return ""
	}

	src := ctx.doc_ctx.syntaxTree.src
	sb := strings.builder_make(context.temp_allocator)

	// Get local variable names from the procedure body that might conflict
	local_vars := collect_local_vars(body, src)
	
	// Get variables at call site that might conflict
	call_site_vars := collect_call_site_vars(ctx.doc_ctx, containing_stmt, src)
	
	// Build rename map for conflicting variables
	local_renames := make(map[string]string, context.temp_allocator)
	for local_var in local_vars {
		if local_var in call_site_vars {
			// Need to rename this variable
			local_renames[local_var] = strings.concatenate({"_", ctx.proc_name, "_", local_var}, context.temp_allocator)
		}
	}

	// Get the indentation of the containing statement
	indent := get_stmt_indentation(containing_stmt, src)
	
	// Determine the context type
	is_value_decl := false
	is_expr_stmt := false
	is_call_arg := false
	target_name := ""
	outer_call: ^ast.Call_Expr = nil
	
	#partial switch s in containing_stmt.derived {
	case ^ast.Value_Decl:
		is_value_decl = true
		if len(s.names) > 0 {
			if ident, ok := s.names[0].derived.(^ast.Ident); ok {
				target_name = ident.name
			}
		}
		// Check if the call is inside another call (argument)
		for value in s.values {
			if outer := find_outer_call(value, call); outer != nil {
				is_call_arg = true
				outer_call = outer
				break
			}
		}
	case ^ast.Expr_Stmt:
		is_expr_stmt = true
		// Check if it's a call containing our target call
		if outer := find_outer_call(s.expr, call); outer != nil && outer != call {
			is_call_arg = true
			outer_call = outer
		}
	case ^ast.Assign_Stmt:
		if len(s.lhs) > 0 {
			if ident, ok := s.lhs[0].derived.(^ast.Ident); ok {
				target_name = ident.name
			}
		}
	}

	// Generate the body statements - strip proc body indentation and use call site indentation
	return_expr := ""
	first_stmt := true
	for stmt in body.stmts {
		#partial switch s in stmt.derived {
		case ^ast.Return_Stmt:
			// Store the return expression for later
			if len(s.results) > 0 {
				result_text := string(src[s.results[0].pos.offset:s.results[0].end.offset])
				return_expr = substitute_params(result_text, param_to_arg, &local_renames)
			}
		case:
			// Get statement text and strip its original indentation
			stmt_text := string(src[stmt.pos.offset:stmt.end.offset])
			substituted := substitute_params(stmt_text, param_to_arg, &local_renames)
			if !first_stmt {
				strings.write_string(&sb, indent)
			}
			strings.write_string(&sb, substituted)
			strings.write_byte(&sb, '\n')
			first_stmt = false
		}
	}
	
	// Generate the final statement
	if is_call_arg && outer_call != nil {
		// Replace the call with the return expression in the outer call
		outer_text := string(src[outer_call.pos.offset:outer_call.end.offset])
		call_text := string(src[call.pos.offset:call.end.offset])
		replaced, _ := strings.replace(outer_text, call_text, return_expr, 1, context.temp_allocator)
		strings.write_string(&sb, indent)
		strings.write_string(&sb, replaced)
	} else if is_value_decl && target_name != "" {
		strings.write_string(&sb, indent)
		strings.write_string(&sb, target_name)
		strings.write_string(&sb, " := ")
		strings.write_string(&sb, return_expr)
	} else if is_expr_stmt {
		// void proc - no final assignment needed, but remove trailing newline
		result := strings.to_string(sb)
		if len(result) > 0 && result[len(result)-1] == '\n' {
			return result[:len(result)-1]
		}
		return result
	} else if target_name != "" {
		strings.write_string(&sb, indent)
		strings.write_string(&sb, target_name)
		strings.write_string(&sb, " = ")
		strings.write_string(&sb, return_expr)
	}

	return strings.to_string(sb)
}

// Find if expr contains call as a nested argument (not as itself)
find_outer_call :: proc(expr: ^ast.Expr, target: ^ast.Call_Expr) -> ^ast.Call_Expr {
	if expr == nil {
		return nil
	}
	
	#partial switch e in expr.derived {
	case ^ast.Call_Expr:
		// Check arguments for the target
		for arg in e.args {
			if arg == target {
				return e  // This call contains our target as an argument
			}
			if nested := find_outer_call(arg, target); nested != nil {
				return nested
			}
		}
	}
	
	return nil
}

// Reindent a multi-line string by stripping original indentation and applying new indentation
reindent_text :: proc(text: string, base_indent: string, extra_indent: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	
	lines := strings.split(text, "\n", context.temp_allocator)
	if len(lines) <= 1 {
		// Single line, no need to reindent
		return text
	}
	
	// Find the minimum indentation of non-empty lines (excluding first line which has no leading indent)
	min_indent := max(int)
	for line, i in lines {
		if i == 0 {
			continue  // First line is already positioned
		}
		if len(strings.trim_space(line)) == 0 {
			continue  // Skip empty lines
		}
		indent_len := 0
		for c in line {
			if c == ' ' || c == '\t' {
				indent_len += 1
			} else {
				break
			}
		}
		min_indent = min(min_indent, indent_len)
	}
	
	if min_indent == max(int) {
		min_indent = 0
	}
	
	for line, i in lines {
		if i == 0 {
			strings.write_string(&sb, line)
			continue
		}
		strings.write_byte(&sb, '\n')
		if len(strings.trim_space(line)) == 0 {
			continue
		}
		strings.write_string(&sb, base_indent)
		strings.write_string(&sb, extra_indent)
		stripped := line
		if len(line) >= min_indent {
			stripped = line[min_indent:]
		}
		strings.write_string(&sb, stripped)
	}
	
	return strings.to_string(sb)
}

// Get the indentation string for a statement
get_stmt_indentation :: proc(stmt: ^ast.Stmt, src: string) -> string {
	if stmt == nil {
		return ""
	}
	return get_line_indentation(src, int(stmt.pos.offset))
}

// Substitute an identifier in text with a new name (word-boundary aware)
substitute_identifier :: proc(text: string, old_name: string, new_name: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	i := 0

	for i < len(text) {
		if is_identifier_start(text[i]) {
			start := i
			for i < len(text) && is_identifier_char(text[i]) {
				i += 1
			}
			ident := text[start:i]

			if ident == old_name {
				is_field := start > 0 && text[start - 1] == '.'
				if !is_field {
					strings.write_string(&sb, new_name)
				} else {
					strings.write_string(&sb, ident)
				}
			} else {
				strings.write_string(&sb, ident)
			}
		} else {
			strings.write_byte(&sb, text[i])
			i += 1
		}
	}

	return strings.to_string(sb)
}

is_identifier_start :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

is_identifier_char :: proc(c: u8) -> bool {
	return is_identifier_start(c) || (c >= '0' && c <= '9')
}

// Collect local variable names declared in a block
collect_local_vars :: proc(body: ^ast.Block_Stmt, src: string, allocator := context.allocator) -> [dynamic]string {
	vars := make([dynamic]string, allocator)
	
	for stmt in body.stmts {
		#partial switch s in stmt.derived {
		case ^ast.Value_Decl:
			for name in s.names {
				if ident, ok := name.derived.(^ast.Ident); ok {
					append(&vars, ident.name)
				}
			}
		}
	}
	
	return vars
}

// Collect variable names visible at the call site
collect_call_site_vars :: proc(doc_ctx: ^documents.Document, containing_stmt: ^ast.Stmt, src: string, allocator := context.allocator) -> map[string]bool {
	vars := make(map[string]bool, allocator)
	
	// Find the block containing the call and collect all variables declared before it
	for decl in doc_ctx.syntaxTree.decls {
		collect_vars_before_stmt(decl, containing_stmt, &vars)
	}
	
	return vars
}

collect_vars_before_stmt :: proc(stmt: ^ast.Stmt, target: ^ast.Stmt, vars: ^map[string]bool) {
	if stmt == nil {
		return
	}
	
	// If we've reached the target, stop
	if stmt == target {
		return
	}
	
	#partial switch s in stmt.derived {
	case ^ast.Value_Decl:
		for value in s.values {
			proc_lit, is_proc := value.derived.(^ast.Proc_Lit)
			if !is_proc {
				continue
			}
			if proc_lit.body == nil || !position_in_node(proc_lit.body, int(target.pos.offset)) {
				continue
			}
			// Target is inside this proc - collect vars in the proc body before target
			collect_vars_before_stmt(proc_lit.body, target, vars)
			return
		}
		// Only collect if this is before the target
		if stmt.pos.offset < target.pos.offset {
			for name in s.names {
				if ident, ok := name.derived.(^ast.Ident); ok {
					vars[ident.name] = true
				}
			}
		}
	case ^ast.Block_Stmt:
		for inner in s.stmts {
			if inner.pos.offset >= target.pos.offset {
				break
			}
			collect_vars_before_stmt(inner, target, vars)
		}
	}
}

// Generate the return statement as an assignment to the target variable
generate_return_as_assignment :: proc(
	ctx: ^InlineProcContext,
	sb: ^strings.Builder,
	ret: ^ast.Return_Stmt,
	containing_stmt: ^ast.Stmt,
	call: ^ast.Call_Expr,
	param_to_arg: map[string]string,
	local_renames: ^map[string]string,
	src: string,
) {
	// Get the target variable name from the containing statement
	target_name := ""
	is_decl := false
	
	#partial switch s in containing_stmt.derived {
	case ^ast.Value_Decl:
		is_decl = true
		if len(s.names) > 0 {
			if ident, ok := s.names[0].derived.(^ast.Ident); ok {
				target_name = ident.name
			}
		}
	case ^ast.Assign_Stmt:
		if len(s.lhs) > 0 {
			if ident, ok := s.lhs[0].derived.(^ast.Ident); ok {
				target_name = ident.name
			}
		}
	}
	
	if target_name == "" || len(ret.results) == 0 {
		return
	}
	
	result_text := string(src[ret.results[0].pos.offset:ret.results[0].end.offset])
	substituted := substitute_params(result_text, param_to_arg, local_renames)
	
	if is_decl {
		strings.write_string(sb, target_name)
		strings.write_string(sb, " := ")
	} else {
		strings.write_string(sb, target_name)
		strings.write_string(sb, " = ")
	}
	strings.write_string(sb, substituted)
}

// Check if a call is a standalone statement (not used as a value)
is_standalone_call :: proc(stmt: ^ast.Stmt, call: ^ast.Call_Expr) -> bool {
	if stmt == nil {
		return false
	}

	#partial switch s in stmt.derived {
	case ^ast.Expr_Stmt:
		// Direct call as statement: foo()
		if s.expr == call {
			return true
		}
	}

	return false
}

// Get the expression from a single return statement if the body is just "return expr"
get_single_return_expr :: proc(body: ^ast.Block_Stmt) -> ^ast.Expr {
	if body == nil || len(body.stmts) != 1 {
		return nil
	}

	if ret, ok := body.stmts[0].derived.(^ast.Return_Stmt); ok {
		if len(ret.results) == 1 {
			return ret.results[0]
		}
	}

	return nil
}

// Substitute parameter names with argument expressions and local variable renames
substitute_params :: proc(text: string, param_to_arg: map[string]string, local_renames: ^map[string]string = nil) -> string {
	if len(param_to_arg) == 0 && (local_renames == nil || len(local_renames) == 0) {
		return text
	}

	result := text
	
	// First apply local variable renames (before parameter substitution)
	// This ensures that if a parameter's argument happens to match a local variable name,
	// we don't accidentally rename the argument
	if local_renames != nil {
		for old_name, new_name in local_renames {
			result = substitute_identifier(result, old_name, new_name)
		}
	}
	
	// Then substitute parameters with arguments
	for param, arg in param_to_arg {
		// Determine if the argument needs parentheses (if it contains operators)
		wrapped_arg := arg
		if needs_parentheses(arg) {
			wrapped_arg = strings.concatenate({"(", arg, ")"}, context.temp_allocator)
		}
		// Simple word-boundary substitution
		result = substitute_identifier(result, param, wrapped_arg)
	}

	return result
}

// Check if an expression needs parentheses when used in place of an identifier
needs_parentheses :: proc(expr: string) -> bool {
	// If the expression contains binary operators, it likely needs parentheses
	// This is a simple heuristic - a full implementation would parse the expression
	paren_depth := 0
	bracket_depth := 0

	for c in expr {
		if c == '(' {
			paren_depth += 1
		} else if c == ')' {
			paren_depth -= 1
		} else if c == '[' {
			bracket_depth += 1
		} else if c == ']' {
			bracket_depth -= 1
		} else if paren_depth == 0 && bracket_depth == 0 {
			// Check for binary operators at the top level
			if c == '+' || c == '-' || c == '*' || c == '/' || c == '%' ||
			   c == '&' || c == '|' || c == '^' || c == '<' || c == '>' {
				return true
			}
		}
	}

	return false
}

// Generate the edit to delete the procedure definition
generate_proc_delete_edit :: proc(ctx: ^InlineProcContext) -> TextEdit {
	src := ctx.doc_ctx.syntaxTree.src

	// Get the range of the entire procedure declaration
	decl_range := common.get_token_range(ctx.proc_decl, src)

	// Extend to include the newline after the procedure if present
	end_offset, _ := common.get_absolute_position(decl_range.end, ctx.doc_ctx.text)
	if end_offset < len(src) && src[end_offset] == '\n' {
		decl_range.end.character += 1
	}

	// Also try to delete any blank line before if the line above is blank
	if decl_range.start.line > 0 {
		// Check if we should delete a preceding newline
		start_offset, _ := common.get_absolute_position(decl_range.start, ctx.doc_ctx.text)
		if start_offset > 0 {
			// Look for newline before
			check_pos := start_offset - 1
			if src[check_pos] == '\n' {
				decl_range.start.line -= 1
				// Find the position of the previous newline
				if column, ok := common.get_last_column(decl_range.start.line, ctx.doc_ctx.text); ok {
					decl_range.start.character = column
				}
			}
		}
	}

	return TextEdit{range = decl_range, newText = ""}
}
