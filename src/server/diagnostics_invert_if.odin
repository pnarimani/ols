package server

import "core:odin/ast"
import "core:strings"

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

// Check document for if statements that could benefit from inversion
check_invert_if_suggestions :: proc(document: ^Document, config: ^common.Config) {
	if !config.enable_invert_if_diagnostics {
		return
	}

	if document == nil || document.ast.decls == nil {
		return
	}

	path := document.uri.path

	when ODIN_OS == .Windows {
		path = common.get_case_sensitive_path(path, context.temp_allocator)
	}

	uri := common.create_uri(path, context.temp_allocator)

	remove_diagnostics(.Hint, uri.uri)

	// Find all if statements that could benefit from inversion
	for decl in document.ast.decls {
		find_invertible_ifs(decl, document, uri.uri)
	}
}

// Recursively search for if statements that could benefit from inversion
find_invertible_ifs :: proc(node: ^ast.Node, document: ^Document, uri: string) {
	if node == nil || node.derived == nil {
		return
	}

	#partial switch n in node.derived {
	case ^ast.If_Stmt:
		if should_suggest_inversion(n, document) {
			add_invert_if_diagnostic(n, document, uri)
		}
		// Also check inside the if body and else clause
		if n.body != nil {
			find_invertible_ifs(n.body, document, uri)
		}
		if n.else_stmt != nil {
			find_invertible_ifs(n.else_stmt, document, uri)
		}

	case ^ast.Block_Stmt:
		for stmt in n.stmts {
			find_invertible_ifs(stmt, document, uri)
		}

	case ^ast.Proc_Lit:
		if n.body != nil {
			find_invertible_ifs(n.body, document, uri)
		}

	case ^ast.Value_Decl:
		for value in n.values {
			find_invertible_ifs(value, document, uri)
		}

	case ^ast.For_Stmt:
		if n.body != nil {
			find_invertible_ifs(n.body, document, uri)
		}

	case ^ast.Range_Stmt:
		if n.body != nil {
			find_invertible_ifs(n.body, document, uri)
		}

	case ^ast.Switch_Stmt:
		if n.body != nil {
			find_invertible_ifs(n.body, document, uri)
		}

	case ^ast.Type_Switch_Stmt:
		if n.body != nil {
			find_invertible_ifs(n.body, document, uri)
		}

	case ^ast.Case_Clause:
		for stmt in n.body {
			find_invertible_ifs(stmt, document, uri)
		}

	case ^ast.When_Stmt:
		if n.body != nil {
			find_invertible_ifs(n.body, document, uri)
		}
		if n.else_stmt != nil {
			find_invertible_ifs(n.else_stmt, document, uri)
		}

	case ^ast.Defer_Stmt:
		if n.stmt != nil {
			find_invertible_ifs(n.stmt, document, uri)
		}
	}
}

// Determine if an if statement should be suggested for inversion
should_suggest_inversion :: proc(if_stmt: ^ast.If_Stmt, document: ^Document) -> bool {
	// Skip else-if chains - too complex to give simple advice
	if is_else_if_chain(if_stmt) {
		return false
	}

	// Check for negated condition pattern: if !condition { ... }
	has_neg := has_negated_condition(if_stmt)
	has_else := if_stmt.else_stmt != nil
	if has_neg && has_else {
		return true
	}

	// Check for guard clause opportunity:
	// if statement with no else, and the body is complex while
	// an early exit could simplify the code
	if if_stmt.else_stmt == nil {
		body_complexity := get_body_complexity(if_stmt.body)
		// If the body is complex (nested ifs, many statements), suggest guard clause
		if body_complexity >= 3 {
			return true
		}
	}

	// Check if else body is much simpler than if body (early exit pattern)
	if if_stmt.else_stmt != nil {
		if_complexity := get_body_complexity(if_stmt.body)
		else_complexity := get_body_complexity(if_stmt.else_stmt)

		// If else is an early exit (1 statement) and if body is complex
		if else_complexity == 1 && if_complexity >= 3 {
			if is_early_exit(if_stmt.else_stmt) {
				return true
			}
		}
	}

	return false
}

// Check if the if statement is part of an else-if chain
is_else_if_chain :: proc(if_stmt: ^ast.If_Stmt) -> bool {
	if if_stmt.else_stmt == nil {
		return false
	}
	_, is_else_if := if_stmt.else_stmt.derived.(^ast.If_Stmt)
	return is_else_if
}

// Check if condition is negated (starts with !)
has_negated_condition :: proc(if_stmt: ^ast.If_Stmt) -> bool {
	if if_stmt.cond == nil {
		return false
	}
	unary, ok := if_stmt.cond.derived.(^ast.Unary_Expr)
	if !ok {
		return false
	}
	return unary.op.kind == .Not
}

// Get a complexity score for a body (rough heuristic)
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
			return is_early_exit_stmt(s.stmts[0])
		}
	}

	return is_early_exit_stmt(stmt)
}

is_early_exit_stmt :: proc(stmt: ^ast.Stmt) -> bool {
	if stmt == nil {
		return false
	}

	#partial switch s in stmt.derived {
	case ^ast.Return_Stmt:
		return true
	case ^ast.Branch_Stmt:
		return true // break, continue, fallthrough
	}

	return false
}

// Add a diagnostic for an if statement that should be inverted
add_invert_if_diagnostic :: proc(if_stmt: ^ast.If_Stmt, document: ^Document, uri: string) {
	if if_stmt == nil || if_stmt.cond == nil {
		return
	}

	if document == nil || document.ast.src == "" {
		return
	}

	message := get_diagnostic_message(if_stmt)

	add_diagnostics(
		.Hint,
		uri,
		Diagnostic {
			range = common.get_token_range(if_stmt.cond^, document.ast.src),
			severity = DiagnosticSeverity.Hint,
			code = INVERT_IF_DIAGNOSTIC_CODE,
			message = message,
			tags = {},
		},
	)
}

// Generate an appropriate message based on why inversion is suggested
get_diagnostic_message :: proc(if_stmt: ^ast.If_Stmt) -> string {
	if has_negated_condition(if_stmt) {
		return "Consider inverting this if statement to remove the negation"
	}

	if if_stmt.else_stmt == nil {
		return "Consider inverting this if statement to use a guard clause"
	}

	return "Consider inverting this if statement for better readability"
}
