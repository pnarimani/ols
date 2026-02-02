package diagnostics

import "src:common"
import "src:documents"

import "core:odin/ast"

/*
 * This diagnostic suggests inverting if statements when it would improve code readability.
 * Specifically, it targets "guard clause" patterns where inverting the condition 
 * allows early exits and reduces nesting.
 *
 * Triggers when:
 * 1. An if statement has no else clause and the body could be an early exit (guard clause opportunity)
 * 2. The if body is significantly more complex/nested than a potential else body
 * 3. A negated condition (!x) could be simplified by inverting
 *
 * Does NOT trigger when:
 * 1. The if statement has an else-if chain
 * 2. Both branches have similar complexity
 * 3. The if body is already a simple early exit (already a guard clause)
 */

INVERT_IF_DIAGNOSTIC_CODE :: "InvertIf"

// Minimum body complexity score to suggest inversion for guard clause pattern
COMPLEXITY_THRESHOLD :: 3

NEGATION_MESSAGE :: "Consider inverting this if statement to remove the negation"
GUARD_CLAUSE_MESSAGE :: "Consider inverting this if statement to use a guard clause"
READABILITY_MESSAGE :: "Consider inverting this if statement for better readability"

Diagnostic_Reason :: enum {
	None,
	Negated_Condition,        // if !x { ... } else { ... }
	Guard_Clause_Opportunity, // Complex body, no else, last in block
	Early_Exit_In_Else,       // Complex if body, else is just return/break
}

Invert_If_Visitor_Data :: struct {
	doc_ctx:      documents.Document,
	encoded_path: string,
}

// Check document for if statements that could benefit from inversion
check_invert_if_suggestions :: proc(doc_ctx: documents.Document, config: ^common.Config) {
	if config == nil || !config.enable_invert_if_diagnostics {
		return
	}

	if doc_ctx.ast.decls == nil {
		return
	}

	// Build encoded path with platform-specific path handling
	path := doc_ctx.path
	when ODIN_OS == .Windows {
		path = common.get_case_sensitive_path(path, context.temp_allocator)
	}
	encoded_path := common.make_encoded_path(path, context.temp_allocator)

	// Clear existing .Hint diagnostics for this path before adding new ones
	begin_diagnostic_update(encoded_path, .Hint)

	visitor_data := Invert_If_Visitor_Data {
		doc_ctx      = doc_ctx,
		encoded_path = encoded_path,
	}

	visit_ast_nodes(doc_ctx.ast.decls[:], invert_if_visitor, &visitor_data)
}

invert_if_visitor :: proc(node: ^ast.Node, ctx: ^AST_Visitor_Context, user_data: rawptr) -> bool {
	if node == nil || ctx == nil || user_data == nil {
		return false
	}

	// Only process if statements
	if_stmt, ok := node.derived.(^ast.If_Stmt)
	if !ok {
		return false // Continue traversal
	}

	data := cast(^Invert_If_Visitor_Data)user_data

	// Check if this if statement should suggest inversion
	reason := get_inversion_reason(if_stmt, ctx.is_last_in_block, ctx.in_if_body)
	if reason == .None {
		return false // Continue traversal
	}

	// Add the diagnostic
	add_invert_if_diagnostic(if_stmt, data.doc_ctx, data.encoded_path, reason)

	return false // Continue to find more
}

// Determine if and why an if statement should be suggested for inversion
get_inversion_reason :: proc(if_stmt: ^ast.If_Stmt, is_last_in_block: bool, in_if_body: bool) -> Diagnostic_Reason {
	if if_stmt == nil {
		return .None
	}

	// Skip else-if chains - too complex to give simple advice
	if is_else_if_chain(if_stmt) {
		return .None
	}

	// Check for negated condition pattern: if !condition { ... } else { ... }
	if check_negated_condition_pattern(if_stmt) {
		return .Negated_Condition
	}

	// Check for guard clause opportunity
	if check_guard_clause_pattern(if_stmt, is_last_in_block, in_if_body) {
		return .Guard_Clause_Opportunity
	}

	// Check for early exit in else pattern
	if check_early_exit_pattern(if_stmt) {
		return .Early_Exit_In_Else
	}

	return .None
}

// Pattern: if !condition { ... } else { ... }
// Suggests removing the negation by swapping branches
check_negated_condition_pattern :: proc(if_stmt: ^ast.If_Stmt) -> bool {
	has_neg := has_negated_condition(if_stmt)
	has_else := if_stmt.else_stmt != nil
	return has_neg && has_else
}

// Pattern: Complex body with no else, last in block, not nested in if
// Suggests using a guard clause for early exit
check_guard_clause_pattern :: proc(if_stmt: ^ast.If_Stmt, is_last_in_block: bool, in_if_body: bool) -> bool {
	if if_stmt.else_stmt != nil {
		return false
	}

	// Must be last statement in the block
	// Otherwise inverting would skip code that comes after
	if !is_last_in_block {
		return false
	}

	// Don't suggest for nested if statements
	// Guard clause pattern only makes sense at top level of function/loop
	if in_if_body {
		return false
	}

	// Body must be complex enough to warrant a guard clause
	body_complexity := get_body_complexity(if_stmt.body)
	return body_complexity >= COMPLEXITY_THRESHOLD
}

// Pattern: Complex if body, else is just a simple early exit (return/break)
// Suggests inverting to put the early exit first
check_early_exit_pattern :: proc(if_stmt: ^ast.If_Stmt) -> bool {
	if if_stmt.else_stmt == nil {
		return false
	}

	if_complexity := get_body_complexity(if_stmt.body)
	else_complexity := get_body_complexity(if_stmt.else_stmt)

	// Else must be a simple early exit (1 statement)
	// If body must be complex
	if else_complexity != 1 || if_complexity < COMPLEXITY_THRESHOLD {
		return false
	}

	return is_early_exit(if_stmt.else_stmt)
}

// Get a complexity score for a body (rough heuristic)
// Higher scores indicate more complex code that might benefit from refactoring
get_body_complexity :: proc(stmt: ^ast.Stmt) -> int {
	if stmt == nil {
		return 0
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		complexity := len(s.stmts)
		// Add extra complexity for nested control structures
		for inner_stmt in s.stmts {
			complexity += get_nested_complexity(inner_stmt)
		}
		return complexity
	case ^ast.If_Stmt:
		return 1 + get_body_complexity(s.body) + get_body_complexity(s.else_stmt)
	}

	return 1
}

// Get additional complexity from nested control structures
get_nested_complexity :: proc(node: ^ast.Node) -> int {
	if node == nil {
		return 0
	}

	#partial switch n in node.derived {
	case ^ast.If_Stmt:
		return 2 + get_body_complexity(n.body)
	case ^ast.For_Stmt, ^ast.Range_Stmt:
		return 2
	case ^ast.Switch_Stmt, ^ast.Type_Switch_Stmt:
		return 2
	}

	return 0
}

// Check if a statement is an early exit (return, break, continue)
is_early_exit :: proc(stmt: ^ast.Stmt) -> bool {
	if stmt == nil {
		return false
	}

	#partial switch s in stmt.derived {
	case ^ast.Block_Stmt:
		if len(s.stmts) == 1 {
			return is_control_flow_stmt(s.stmts[0])
		}
		return false
	}

	return is_control_flow_stmt(stmt)
}

// Add a diagnostic for an if statement that should be inverted
add_invert_if_diagnostic :: proc(if_stmt: ^ast.If_Stmt, doc_ctx: documents.Document, encoded_path: string, reason: Diagnostic_Reason) {
	if if_stmt == nil {
		return
	}

	if if_stmt.cond == nil {
		return
	}

	if doc_ctx.ast.src == "" {
		return
	}

	message := get_diagnostic_message(reason)

	add_diagnostic(
		.Hint,
		encoded_path,
		Diagnostic {
			range = common.get_token_range(if_stmt.cond^, doc_ctx.ast.src),
			severity = DiagnosticSeverity.Hint,
			code = INVERT_IF_DIAGNOSTIC_CODE,
			message = message,
			tags = {},
		},
	)
}

get_diagnostic_message :: proc(reason: Diagnostic_Reason) -> string {
	switch reason {
	case .Negated_Condition:
		return NEGATION_MESSAGE
	case .Guard_Clause_Opportunity:
		return GUARD_CLAUSE_MESSAGE
	case .Early_Exit_In_Else:
		return READABILITY_MESSAGE
	case .None:
		return READABILITY_MESSAGE
	}
	return READABILITY_MESSAGE
}

// ============================================================================
// AST Visitor utilities (moved from action_utils.odin)
// ============================================================================

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
