package server

import "core:odin/ast"

import "src:common"

// Create a WorkspaceEdit with text edits for a single URI.
// This is the standard pattern used by all code actions.
make_workspace_edit :: proc(uri: common.FileUri, edits: []TextEdit) -> WorkspaceEdit {
	edit: WorkspaceEdit
	edit.changes = make(map[common.FileUri][]TextEdit, 0, context.temp_allocator)
	edit.changes[uri] = edits
	return edit
}

// Get the indentation (leading whitespace) of the line containing the given offset
get_line_indentation :: proc(src: string, offset: int) -> string {
	line_start := offset
	for line_start > 0 && src[line_start - 1] != '\n' {
		line_start -= 1
	}

	indent_end := line_start
	for indent_end < len(src) && (src[indent_end] == ' ' || src[indent_end] == '\t') {
		indent_end += 1
	}

	return src[line_start:indent_end]
}

// Find the innermost procedure containing the given position.
// Searches through all declarations to find a Proc_Lit that contains the position.
find_containing_proc :: proc(stmts: []^ast.Stmt, position: common.AbsolutePosition) -> ^ast.Proc_Lit {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if result := find_proc_in_node(stmt, position); result != nil {
			return result
		}
	}
	return nil
}

@(private = "file")
find_proc_in_node :: proc(node: ^ast.Node, position: common.AbsolutePosition) -> ^ast.Proc_Lit {
	if node == nil {
		return nil
	}

	if !position_in_node(node, position) {
		return nil
	}

	#partial switch n in node.derived {
	case ^ast.Value_Decl:
		for value in n.values {
			if result := find_proc_in_node(value, position); result != nil {
				return result
			}
		}

	case ^ast.Proc_Lit:
		if n.body != nil {
			if block, ok := n.body.derived.(^ast.Block_Stmt); ok {
				if nested := find_proc_in_block(block, position); nested != nil {
					return nested
				}
			}
		}
		return n

	case ^ast.Block_Stmt:
		return find_proc_in_block(n, position)
	}

	return nil
}

@(private = "file")
find_proc_in_block :: proc(block: ^ast.Block_Stmt, position: common.AbsolutePosition) -> ^ast.Proc_Lit {
	if block == nil {
		return nil
	}

	for stmt in block.stmts {
		if result := find_proc_in_node(stmt, position); result != nil {
			return result
		}
	}
	return nil
}

// Check if a statement is a control flow statement (return, break, continue, fallthrough)
is_control_flow_stmt :: proc(stmt: ^ast.Stmt) -> bool {
	if stmt == nil {
		return false
	}
	#partial switch _ in stmt.derived {
	case ^ast.Return_Stmt, ^ast.Branch_Stmt:
		return true
	}
	return false
}

// Check if a block body ends with a control flow statement
body_ends_with_control_flow :: proc(stmt: ^ast.Stmt) -> bool {
	if stmt == nil {
		return false
	}

	#partial switch block in stmt.derived {
	case ^ast.Block_Stmt:
		if len(block.stmts) == 0 {
			return false
		}
		last_stmt := block.stmts[len(block.stmts) - 1]
		return is_control_flow_stmt(last_stmt)
	}

	return is_control_flow_stmt(stmt)
}

// Check if the if statement has an else-if chain
is_else_if_chain :: proc(if_stmt: ^ast.If_Stmt) -> bool {
	if if_stmt == nil || if_stmt.else_stmt == nil {
		return false
	}
	_, is_else_if := if_stmt.else_stmt.derived.(^ast.If_Stmt)
	return is_else_if
}

// Check if condition is negated (!x)
has_negated_condition :: proc(if_stmt: ^ast.If_Stmt) -> bool {
	if if_stmt == nil || if_stmt.cond == nil {
		return false
	}
	unary, ok := if_stmt.cond.derived.(^ast.Unary_Expr)
	if !ok {
		return false
	}
	return unary.op.kind == .Not
}

// Context passed through AST traversal
AST_Visitor_Context :: struct {
	in_loop:          bool, // Inside for/range loop
	in_proc:          bool, // Inside procedure body
	in_if_body:       bool, // Inside an if statement body
	is_last_in_block: bool, // Last statement in containing block
}

// Callback type for visiting nodes
// Return true to stop traversal, false to continue
AST_Visitor_Callback :: #type proc(node: ^ast.Node, ctx: ^AST_Visitor_Context, user_data: rawptr) -> bool

// Visit all nodes in AST with context tracking
// Returns true if traversal was stopped early by callback
visit_ast_nodes :: proc(
	stmts: []^ast.Stmt,
	callback: AST_Visitor_Callback,
	user_data: rawptr,
	ctx: ^AST_Visitor_Context = nil,
) -> bool {
	local_ctx: AST_Visitor_Context
	active_ctx := ctx if ctx != nil else &local_ctx

	return visit_stmts_internal(stmts, callback, user_data, active_ctx, true)
}

@(private = "file")
visit_stmts_internal :: proc(
	stmts: []^ast.Stmt,
	callback: AST_Visitor_Callback,
	user_data: rawptr,
	ctx: ^AST_Visitor_Context,
	parent_is_last: bool,
) -> bool {
	for stmt, i in stmts {
		if stmt == nil {
			continue
		}
		is_last := i == len(stmts) - 1
		ctx.is_last_in_block = is_last && parent_is_last
		if visit_node_internal(stmt, callback, user_data, ctx) {
			return true
		}
	}
	return false
}

@(private = "file")
visit_node_internal :: proc(
	node: ^ast.Node,
	callback: AST_Visitor_Callback,
	user_data: rawptr,
	ctx: ^AST_Visitor_Context,
) -> bool {
	if node == nil || node.derived == nil {
		return false
	}

	// Call the visitor callback first
	if callback(node, ctx, user_data) {
		return true
	}

	// Recurse into children based on node type
	#partial switch n in node.derived {
	case ^ast.Block_Stmt:
		return visit_stmts_internal(n.stmts, callback, user_data, ctx, ctx.is_last_in_block)

	case ^ast.Proc_Lit:
		if n.body == nil {
			return false
		}
		// Fresh scope for procedure - reset context flags
		old_in_proc, old_in_loop, old_in_if := ctx.in_proc, ctx.in_loop, ctx.in_if_body
		ctx.in_proc = true
		ctx.in_loop = false
		ctx.in_if_body = false
		defer {
			ctx.in_proc = old_in_proc
			ctx.in_loop = old_in_loop
			ctx.in_if_body = old_in_if
		}
		return visit_node_internal(n.body, callback, user_data, ctx)

	case ^ast.Value_Decl:
		for value in n.values {
			if visit_node_internal(value, callback, user_data, ctx) {
				return true
			}
		}

	case ^ast.If_Stmt:
		if n.body != nil {
			old_in_if := ctx.in_if_body
			ctx.in_if_body = true
			defer ctx.in_if_body = old_in_if
			if visit_node_internal(n.body, callback, user_data, ctx) {
				return true
			}
		}
		if n.else_stmt != nil {
			if visit_node_internal(n.else_stmt, callback, user_data, ctx) {
				return true
			}
		}

	case ^ast.For_Stmt:
		if n.body == nil {
			return false
		}
		old_in_loop, old_in_if := ctx.in_loop, ctx.in_if_body
		ctx.in_loop = true
		ctx.in_if_body = false
		defer {
			ctx.in_loop = old_in_loop
			ctx.in_if_body = old_in_if
		}
		return visit_node_internal(n.body, callback, user_data, ctx)

	case ^ast.Range_Stmt:
		if n.body == nil {
			return false
		}
		old_in_loop, old_in_if := ctx.in_loop, ctx.in_if_body
		ctx.in_loop = true
		ctx.in_if_body = false
		defer {
			ctx.in_loop = old_in_loop
			ctx.in_if_body = old_in_if
		}
		return visit_node_internal(n.body, callback, user_data, ctx)

	case ^ast.Switch_Stmt:
		if n.body != nil {
			return visit_node_internal(n.body, callback, user_data, ctx)
		}

	case ^ast.Type_Switch_Stmt:
		if n.body != nil {
			return visit_node_internal(n.body, callback, user_data, ctx)
		}

	case ^ast.Case_Clause:
		return visit_stmts_internal(n.body, callback, user_data, ctx, ctx.is_last_in_block)

	case ^ast.When_Stmt:
		if n.body != nil && visit_node_internal(n.body, callback, user_data, ctx) {
			return true
		}
		if n.else_stmt != nil {
			return visit_node_internal(n.else_stmt, callback, user_data, ctx)
		}

	case ^ast.Defer_Stmt:
		if n.stmt != nil {
			return visit_node_internal(n.stmt, callback, user_data, ctx)
		}
	}

	return false
}
