#+private file
package server

import "src:documents"
import "core:odin/ast"

import "src:common"

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
	Negated_Condition,     // if !x { ... } else { ... }
	Guard_Clause_Opportunity, // Complex body, no else, last in block
	Early_Exit_In_Else,    // Complex if body, else is just return/break
}

Invert_If_Visitor_Data :: struct {
	doc_ctx:    documents.Document,
	uri:        string,
	collection: ^DiagnosticCollection,
}

// Check document for if statements that could benefit from inversion
@(private = "package")
check_invert_if_suggestions :: proc(doc_ctx: documents.Document, config: ^common.Config, collection: ^DiagnosticCollection) {
	if config == nil || !config.enable_invert_if_diagnostics {
		return
	}

	if doc_ctx.ast.decls == nil {
		return
	}

	// Build URI with platform-specific path handling
	path := doc_ctx.uri.path
	when ODIN_OS == .Windows {
		path = common.get_case_sensitive_path(path, context.temp_allocator)
	}
	uri := common.create_uri(path, context.temp_allocator)

	visitor_data := Invert_If_Visitor_Data {
		doc_ctx    = doc_ctx,
		uri        = uri.uri,
		collection = collection,
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
	add_invert_if_diagnostic(if_stmt, data.doc_ctx, data.uri, reason, data.collection)

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
add_invert_if_diagnostic :: proc(if_stmt: ^ast.If_Stmt, doc_ctx: documents.Document, uri: string, reason: Diagnostic_Reason, collection: ^DiagnosticCollection) {
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
		collection,
		.Hint,
		uri,
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
