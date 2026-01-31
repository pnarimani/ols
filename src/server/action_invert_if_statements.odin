#+private file

package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/tokenizer"
import path "core:path/slashpath"
import "core:strings"

import "src:common"

/*
 * The general idea behind inverting if statements is to allow 
 * if statements to be inverted without changing their behavior.
 * The examples of these changes are provided in the tests.
 * We should be careful to only allow this code action when it is safe to do so.
 * So for now, we only support only one level of if statements without else-if chains.
 */

@(private="package")
add_invert_if_action :: proc(
	document: ^Document,
	position: common.AbsolutePosition,
	uri: string,
	actions: ^[dynamic]CodeAction,
) {
	if_stmt, ctx, following_stmts, can_early_return := find_if_stmt_at_position(document.ast.decls[:], position)
	if if_stmt == nil {
		return
	}

	new_text, ok := generate_inverted_if(document, if_stmt, ctx, following_stmts, can_early_return)
	if !ok {
		return
	}

	// Compute the range - if we have following statements and the body ends with control flow,
	// we need to include those in the range
	range: common.Range
	if len(following_stmts) > 0 && body_ends_with_control_flow(if_stmt.body) && if_stmt.else_stmt == nil {
		// Extend range to include all following statements
		last_stmt := following_stmts[len(following_stmts) - 1]
		range.start = common.token_pos_to_position(if_stmt.pos, document.ast.src)
		end_pos := last_stmt.end
		end_pos.offset -= 1
		range.end = common.token_pos_to_position(end_pos, document.ast.src)
	} else {
		range = common.get_token_range(if_stmt^, document.ast.src)
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)
	append(&textEdits, TextEdit{range = range, newText = new_text})

	append(
		actions,
		CodeAction {
			kind = "refactor.more",
			isPreferred = false,
			title = "Invert if",
			edit = make_workspace_edit(uri, textEdits[:]),
		},
	)
}

// Find the innermost if statement that contains the given position
// This will NOT return else-if statements, only top-level if statements
// Also will not return an if statement if the position is in its else clause
// Also returns the control flow context (proc or loop), any statements following the if in the parent block,
// and whether it's safe to use early return (no code after the if at any level up to the proc/loop)
find_if_stmt_at_position :: proc(stmts: []^ast.Stmt, position: common.AbsolutePosition) -> (^ast.If_Stmt, Control_Flow_Context, []^ast.Stmt, bool) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if result, ctx, following, can_early_return := find_if_stmt_in_node(stmt, position, false, .Proc, true); result != nil {
			return result, ctx, following, can_early_return
		}
	}
	return nil, .Proc, nil, false
}

find_if_stmt_in_node :: proc(node: ^ast.Node, position: common.AbsolutePosition, in_else_clause: bool, ctx: Control_Flow_Context, is_last_in_parent: bool) -> (^ast.If_Stmt, Control_Flow_Context, []^ast.Stmt, bool) {
	if node == nil {
		return nil, ctx, nil, false
	}

	if !(node.pos.offset <= position && position <= node.end.offset) {
		return nil, ctx, nil, false
	}

	#partial switch n in node.derived {
	case ^ast.If_Stmt:
		// First check if position is in the else clause
		if n.else_stmt != nil && position_in_node(n.else_stmt, position) {
			// Position is in the else clause - look for nested ifs inside it
			// but mark that we're in an else clause
			// The else clause is "last" if this whole if is last
			if nested, nested_ctx, following, can_early := find_if_stmt_in_node(n.else_stmt, position, true, ctx, is_last_in_parent); nested != nil {
				return nested, nested_ctx, following, can_early
			}
			// Position is in else clause but not on a valid nested if
			// Don't return the current if statement
			return nil, ctx, nil, false
		}

		if n.body != nil && position_in_node(n.body, position) {
			// If there's an else clause, we can't early return from the then-body
			// because the else-body might need to execute
			body_is_last := is_last_in_parent && n.else_stmt == nil
			if nested, nested_ctx, following, can_early := find_if_stmt_in_node(n.body, position, false, ctx, body_is_last); nested != nil {
				return nested, nested_ctx, following, can_early
			}
			// Position is inside the body but no nested if found
			// Don't return the current if statement
			return nil, ctx, nil, false
		}

		// Position is in the condition/init part or we're the closest if
		// Only return this if statement if we're NOT in an else clause
		// (i.e., this is not an else-if)
		if !in_else_clause {
			// Note: following statements will be filled in by the Block_Stmt case that called us
			// can_early_return will be determined by the caller based on position in block
			return n, ctx, nil, is_last_in_parent
		}
		return nil, ctx, nil, false

	case ^ast.Block_Stmt:
		for stmt, i in n.stmts {
			is_last := i == len(n.stmts) - 1
			if result, result_ctx, _, _ := find_if_stmt_in_node(stmt, position, false, ctx, is_last && is_last_in_parent); result != nil {
				// Return the following statements in this block
				following := n.stmts[i+1:]
				// Can only early return if this is the last statement AND parent allows early return
				can_early := is_last && is_last_in_parent
				return result, result_ctx, following, can_early
			}
		}

	case ^ast.Proc_Lit:
		if n.body != nil {
			// Proc body is always "last" for purposes of early return
			return find_if_stmt_in_node(n.body, position, false, .Proc, true)
		}

	case ^ast.Value_Decl:
		for value in n.values {
			if result, result_ctx, following, can_early := find_if_stmt_in_node(value, position, false, ctx, is_last_in_parent); result != nil {
				return result, result_ctx, following, can_early
			}
		}

	case ^ast.For_Stmt:
		if n.body != nil {
			// For loop body is "last" for purposes of continue
			return find_if_stmt_in_node(n.body, position, false, .For_Loop, true)
		}

	case ^ast.Range_Stmt:
		if n.body != nil {
			// Range loop body is "last" for purposes of continue
			return find_if_stmt_in_node(n.body, position, false, .For_Loop, true)
		}

	case ^ast.Switch_Stmt:
		if n.body != nil {
			return find_if_stmt_in_node(n.body, position, false, ctx, is_last_in_parent)
		}

	case ^ast.Type_Switch_Stmt:
		if n.body != nil {
			return find_if_stmt_in_node(n.body, position, false, ctx, is_last_in_parent)
		}

	case ^ast.Case_Clause:
		for stmt, i in n.body {
			is_last := i == len(n.body) - 1
			if result, result_ctx, _, _ := find_if_stmt_in_node(stmt, position, false, ctx, is_last && is_last_in_parent); result != nil {
				following := n.body[i+1:]
				can_early := is_last && is_last_in_parent
				return result, result_ctx, following, can_early
			}
		}

	case ^ast.When_Stmt:
		if n.body != nil {
			if result, result_ctx, following, can_early := find_if_stmt_in_node(n.body, position, false, ctx, is_last_in_parent); result != nil {
				return result, result_ctx, following, can_early
			}
		}
		if n.else_stmt != nil {
			if result, result_ctx, following, can_early := find_if_stmt_in_node(n.else_stmt, position, false, ctx, is_last_in_parent); result != nil {
				return result, result_ctx, following, can_early
			}
		}

	case ^ast.Defer_Stmt:
		if n.stmt != nil {
			return find_if_stmt_in_node(n.stmt, position, false, ctx, is_last_in_parent)
		}
	}

	return nil, ctx, nil, false
}

// Check if a block body ends with a control flow statement (return, continue, break, fallthrough)
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
		if last_stmt == nil {
			return false
		}
		return is_control_flow_stmt(last_stmt)
	}

	return is_control_flow_stmt(stmt)
}

// Check if a statement is a control flow statement
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

// Context type for determining which control flow statement to use
Control_Flow_Context :: enum {
	Proc,      // Use return
	For_Loop,  // Use continue
	// Can be extended for break, etc.
}

// Generate the inverted if statement text
generate_inverted_if :: proc(document: ^Document, if_stmt: ^ast.If_Stmt, ctx: Control_Flow_Context = .Proc, following_stmts: []^ast.Stmt = nil, can_early_return: bool = true) -> (string, bool) {
	src := document.ast.src

	indent := get_line_indentation(src, if_stmt.pos.offset)

	sb := strings.builder_make(context.temp_allocator)

	if if_stmt.label != nil {
		label_text := src[if_stmt.label.pos.offset:if_stmt.label.end.offset]
		strings.write_string(&sb, label_text)
		strings.write_string(&sb, ": ")
	}

	strings.write_string(&sb, "if ")

	if if_stmt.init != nil {
		init_text := src[if_stmt.init.pos.offset:if_stmt.init.end.offset]
		strings.write_string(&sb, init_text)
		strings.write_string(&sb, "; ")
	}

	if if_stmt.cond != nil {
		inverted_cond, ok := invert_condition(src, if_stmt.cond)
		if !ok {
			return "", false
		}
		strings.write_string(&sb, inverted_cond)
	}

	strings.write_string(&sb, " ")

	// Now we need to swap the bodies

	if if_stmt.else_stmt != nil {
		// Check if the then-body (which becomes else after inversion) ends with a control flow statement
		// If so, we can remove the redundant else block
		if body_ends_with_control_flow(if_stmt.body) {
			// The then-body ends with control flow, so after inversion:
			// - Put the else-body in the if block
			// - Unwrap the then-body after the if statement
			else_body_text := get_block_body_text(src, if_stmt.else_stmt, indent)
			then_body_text := get_block_body_text_at_indent(src, if_stmt.body, indent)
			// Remove trailing newline to avoid double-newline with source
			then_body_text = strings.trim_right(then_body_text, "\n")

			strings.write_string(&sb, "{\n")
			strings.write_string(&sb, else_body_text)
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}\n")
			// Append the original then-body after the if statement (unwrapped)
			strings.write_string(&sb, then_body_text)
		} else {
			// Standard swap: else becomes then, then becomes else
			else_body_text := get_block_body_text(src, if_stmt.else_stmt, indent)
			then_body_text := get_block_body_text(src, if_stmt.body, indent)

			strings.write_string(&sb, "{\n")
			strings.write_string(&sb, else_body_text)
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "} else {\n")
			strings.write_string(&sb, then_body_text)
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "}")
		}
	} else if body_ends_with_control_flow(if_stmt.body) && len(following_stmts) > 0 {
		// Special case: no else block, but body ends with control flow and there are following statements
		// The following statements act as the implicit "else" branch
		// After inversion:
		// - New if body: following statements + control flow from original body
		// - New following: original body without the control flow
		
		// Get the original body statements without the trailing control flow
		then_body_without_control := get_block_body_without_last_stmt_at_indent(src, if_stmt.body, indent)
		then_body_without_control = strings.trim_right(then_body_without_control, "\n")
		
		// Get the control flow statement from the original body
		control_flow_text := get_last_stmt_text(src, if_stmt.body, indent)
		
		// Build the new if body: following statements + control flow
		strings.write_string(&sb, "{\n")
		for s in following_stmts {
			if s == nil {
				continue
			}
			stmt_text := src[s.pos.offset:s.end.offset]
			strings.write_string(&sb, indent)
			strings.write_string(&sb, "\t")
			strings.write_string(&sb, stmt_text)
			strings.write_string(&sb, "\n")
		}
		strings.write_string(&sb, indent)
		strings.write_string(&sb, "\t")
		strings.write_string(&sb, control_flow_text)
		strings.write_string(&sb, "\n")
		strings.write_string(&sb, indent)
		strings.write_string(&sb, "}\n")
		
		// Append the original body (without control flow) after the if
		strings.write_string(&sb, then_body_without_control)
	} else if can_early_return {
		// No else block and safe to use early return/continue pattern
		// Get the body text at the if-statement's indentation level (one level less than body)
		then_body_text := get_block_body_text_at_indent(src, if_stmt.body, indent)
		// Remove trailing newline to avoid double-newline with source
		then_body_text = strings.trim_right(then_body_text, "\n")
		
		control_flow_stmt := ctx == .For_Loop ? "continue" : "return"

		strings.write_string(&sb, "{\n")
		strings.write_string(&sb, indent)
		strings.write_string(&sb, "\t")
		strings.write_string(&sb, control_flow_stmt)
		strings.write_string(&sb, "\n")
		strings.write_string(&sb, indent)
		strings.write_string(&sb, "}\n")
		// Append the original body after the if statement (unwrapped)
		strings.write_string(&sb, then_body_text)
	} else {
		// No else block but NOT safe to use early return
		// Use standard if-else swap with empty if body
		then_body_text := get_block_body_text(src, if_stmt.body, indent)

		strings.write_string(&sb, "{\n")
		strings.write_string(&sb, indent)
		strings.write_string(&sb, "} else {\n")
		strings.write_string(&sb, then_body_text)
		strings.write_string(&sb, indent)
		strings.write_string(&sb, "}")
	}

	return strings.to_string(sb), true
}

// Extract the body text from a block statement (without the braces)
get_block_body_text :: proc(src: string, stmt: ^ast.Stmt, base_indent: string) -> string {
	if stmt == nil {
		return ""
	}

	#partial switch block in stmt.derived {
	case ^ast.Block_Stmt:
		if len(block.stmts) == 0 {
			return ""
		}

		sb := strings.builder_make(context.temp_allocator)

		for s in block.stmts {
			if s == nil {
				continue
			}
			stmt_indent := get_line_indentation(src, s.pos.offset)
			stmt_text := src[s.pos.offset:s.end.offset]
			strings.write_string(&sb, stmt_indent)
			strings.write_string(&sb, stmt_text)
			strings.write_string(&sb, "\n")
		}

		return strings.to_string(sb)

	case ^ast.If_Stmt:
		// This is an else-if, need to handle it recursively
		if_text, ok := generate_inverted_if_for_else(src, block, base_indent)
		if ok {
			return if_text
		}
	}

	// Fallback: just return the statement text
	stmt_text := src[stmt.pos.offset:stmt.end.offset]
	return fmt.tprintf("%s%s\n", base_indent, stmt_text)
}

// Extract the body text at a specific indentation level (for unwrapping)
get_block_body_text_at_indent :: proc(src: string, stmt: ^ast.Stmt, target_indent: string) -> string {
	if stmt == nil {
		return ""
	}

	#partial switch block in stmt.derived {
	case ^ast.Block_Stmt:
		if len(block.stmts) == 0 {
			return ""
		}

		sb := strings.builder_make(context.temp_allocator)

		for s in block.stmts {
			if s == nil {
				continue
			}
			stmt_text := src[s.pos.offset:s.end.offset]
			strings.write_string(&sb, target_indent)
			strings.write_string(&sb, stmt_text)
			strings.write_string(&sb, "\n")
		}

		return strings.to_string(sb)
	}

	// Fallback: just return the statement text at target indent
	stmt_text := src[stmt.pos.offset:stmt.end.offset]
	return fmt.tprintf("%s%s\n", target_indent, stmt_text)
}

// Extract the body text at a specific indentation level, excluding the last statement
get_block_body_without_last_stmt_at_indent :: proc(src: string, stmt: ^ast.Stmt, target_indent: string) -> string {
	if stmt == nil {
		return ""
	}

	#partial switch block in stmt.derived {
	case ^ast.Block_Stmt:
		if len(block.stmts) <= 1 {
			return ""
		}

		sb := strings.builder_make(context.temp_allocator)

		for s in block.stmts[:len(block.stmts)-1] {
			if s == nil {
				continue
			}
			stmt_text := src[s.pos.offset:s.end.offset]
			strings.write_string(&sb, target_indent)
			strings.write_string(&sb, stmt_text)
			strings.write_string(&sb, "\n")
		}

		return strings.to_string(sb)
	}

	return ""
}

// Get the text of the last statement in a block
get_last_stmt_text :: proc(src: string, stmt: ^ast.Stmt, target_indent: string) -> string {
	if stmt == nil {
		return ""
	}

	#partial switch block in stmt.derived {
	case ^ast.Block_Stmt:
		if len(block.stmts) == 0 {
			return ""
		}
		last_stmt := block.stmts[len(block.stmts) - 1]
		if last_stmt == nil {
			return ""
		}
		return src[last_stmt.pos.offset:last_stmt.end.offset]
	}

	return ""
}

// For else-if chains, we don't invert them, just preserve but re-indent
generate_inverted_if_for_else :: proc(src: string, if_stmt: ^ast.If_Stmt, base_indent: string) -> (string, bool) {
	sb := strings.builder_make(context.temp_allocator)
	body_indent := strings.concatenate({base_indent, "\t"}, context.temp_allocator)
	
	// Write "if <cond> {"
	strings.write_string(&sb, body_indent)
	strings.write_string(&sb, "if ")
	
	if if_stmt.init != nil {
		init_text := src[if_stmt.init.pos.offset:if_stmt.init.end.offset]
		strings.write_string(&sb, init_text)
		strings.write_string(&sb, "; ")
	}
	
	if if_stmt.cond != nil {
		cond_text := src[if_stmt.cond.pos.offset:if_stmt.cond.end.offset]
		strings.write_string(&sb, cond_text)
	}
	
	strings.write_string(&sb, " {\n")
	
	// Write the body with increased indentation
	if if_stmt.body != nil {
		nested_indent := strings.concatenate({body_indent, "\t"}, context.temp_allocator)
		body_text := get_block_body_text_reindented(src, if_stmt.body, nested_indent)
		strings.write_string(&sb, body_text)
	}
	
	strings.write_string(&sb, body_indent)
	
	// Handle else/else-if
	if if_stmt.else_stmt != nil {
		#partial switch else_block in if_stmt.else_stmt.derived {
		case ^ast.If_Stmt:
			// else-if: recursively handle
			strings.write_string(&sb, "} else ")
			else_if_text, ok := generate_inverted_if_for_else_inline(src, else_block, body_indent)
			if !ok {
				return "", false
			}
			strings.write_string(&sb, else_if_text)
		case ^ast.Block_Stmt:
			// else block
			strings.write_string(&sb, "} else {\n")
			nested_indent := strings.concatenate({body_indent, "\t"}, context.temp_allocator)
			else_text := get_block_body_text_reindented(src, if_stmt.else_stmt, nested_indent)
			strings.write_string(&sb, else_text)
			strings.write_string(&sb, body_indent)
			strings.write_string(&sb, "}\n")
		}
	} else {
		strings.write_string(&sb, "}\n")
	}
	
	return strings.to_string(sb), true
}

// Helper for else-if chains (without leading indent, as it follows "} else ")
generate_inverted_if_for_else_inline :: proc(src: string, if_stmt: ^ast.If_Stmt, base_indent: string) -> (string, bool) {
	sb := strings.builder_make(context.temp_allocator)
	
	// Write "if <cond> {"
	strings.write_string(&sb, "if ")
	
	if if_stmt.init != nil {
		init_text := src[if_stmt.init.pos.offset:if_stmt.init.end.offset]
		strings.write_string(&sb, init_text)
		strings.write_string(&sb, "; ")
	}
	
	if if_stmt.cond != nil {
		cond_text := src[if_stmt.cond.pos.offset:if_stmt.cond.end.offset]
		strings.write_string(&sb, cond_text)
	}
	
	strings.write_string(&sb, " {\n")
	
	// Write the body with increased indentation
	if if_stmt.body != nil {
		nested_indent := strings.concatenate({base_indent, "\t"}, context.temp_allocator)
		body_text := get_block_body_text_reindented(src, if_stmt.body, nested_indent)
		strings.write_string(&sb, body_text)
	}
	
	strings.write_string(&sb, base_indent)
	
	// Handle else/else-if
	if if_stmt.else_stmt != nil {
		#partial switch else_block in if_stmt.else_stmt.derived {
		case ^ast.If_Stmt:
			// else-if: recursively handle
			strings.write_string(&sb, "} else ")
			else_if_text, ok := generate_inverted_if_for_else_inline(src, else_block, base_indent)
			if !ok {
				return "", false
			}
			strings.write_string(&sb, else_if_text)
		case ^ast.Block_Stmt:
			// else block
			strings.write_string(&sb, "} else {\n")
			nested_indent := strings.concatenate({base_indent, "\t"}, context.temp_allocator)
			else_text := get_block_body_text_reindented(src, if_stmt.else_stmt, nested_indent)
			strings.write_string(&sb, else_text)
			strings.write_string(&sb, base_indent)
			strings.write_string(&sb, "}\n")
		}
	} else {
		strings.write_string(&sb, "}\n")
	}
	
	return strings.to_string(sb), true
}

// Get block body text with specific indentation (re-indenting all statements)
get_block_body_text_reindented :: proc(src: string, stmt: ^ast.Stmt, target_indent: string) -> string {
	if stmt == nil {
		return ""
	}

	#partial switch block in stmt.derived {
	case ^ast.Block_Stmt:
		if len(block.stmts) == 0 {
			return ""
		}

		sb := strings.builder_make(context.temp_allocator)

		for s in block.stmts {
			if s == nil {
				continue
			}
			stmt_text := src[s.pos.offset:s.end.offset]
			strings.write_string(&sb, target_indent)
			strings.write_string(&sb, stmt_text)
			strings.write_string(&sb, "\n")
		}

		return strings.to_string(sb)
	}

	// Fallback: just return the statement text at target indent
	stmt_text := src[stmt.pos.offset:stmt.end.offset]
	return fmt.tprintf("%s%s\n", target_indent, stmt_text)
}

// Invert a condition expression
invert_condition :: proc(src: string, cond: ^ast.Expr) -> (string, bool) {
	if cond == nil {
		return "", false
	}

	#partial switch c in cond.derived {
	case ^ast.Binary_Expr:
		inverted_op, can_invert := get_inverted_operator(c.op.kind)
		if can_invert {
			left_text := src[c.left.pos.offset:c.left.end.offset]
			right_text := src[c.right.pos.offset:c.right.end.offset]
			return fmt.tprintf("%s %s %s", left_text, inverted_op, right_text), true
		}

		if c.op.kind == .Cmp_And || c.op.kind == .Cmp_Or {
			// Just wrap with !()
			cond_text := src[cond.pos.offset:cond.end.offset]
			return fmt.tprintf("!(%s)", cond_text), true
		}

	case ^ast.Unary_Expr:
		// If it's already negated with !, remove the negation
		if c.op.kind == .Not {
			inner_text := src[c.expr.pos.offset:c.expr.end.offset]
			return inner_text, true
		}

	case ^ast.Paren_Expr:
		inner_inverted, ok := invert_condition(src, c.expr)
		if ok {
			if needs_parentheses(inner_inverted) {
				return fmt.tprintf("(%s)", inner_inverted), true
			}
			return inner_inverted, true
		}
	}

	// Default: wrap the whole condition with !()
	cond_text := src[cond.pos.offset:cond.end.offset]
	if is_simple_expr(cond) {
		return fmt.tprintf("!%s", cond_text), true
	}
	return fmt.tprintf("!(%s)", cond_text), true
}

// Check if an expression is simple (identifier, call, or already parenthesized)
is_simple_expr :: proc(expr: ^ast.Expr) -> bool {
	if expr == nil {
		return false
	}
	#partial switch e in expr.derived {
	case ^ast.Ident, ^ast.Paren_Expr, ^ast.Call_Expr, ^ast.Selector_Expr, ^ast.Index_Expr:
		return true
	}
	return false
}

// Check if a string needs parentheses (simple heuristic)
needs_parentheses :: proc(s: string) -> bool {
	// If it starts with ! and is not wrapped in parens, it might need them
	// This is a simple heuristic
	return strings.contains(s, " && ") || strings.contains(s, " || ")
}

// Get the inverted comparison operator
get_inverted_operator :: proc(op: tokenizer.Token_Kind) -> (string, bool) {
	#partial switch op {
	case .Cmp_Eq:
		return "!=", true
	case .Not_Eq:
		return "==", true
	case .Lt:
		return ">=", true
	case .Lt_Eq:
		return ">", true
	case .Gt:
		return "<=", true
	case .Gt_Eq:
		return "<", true
	}
	return "", false
}
