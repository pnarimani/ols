#+private file

package server

import "src:documents"
import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/tokenizer"
import path "core:path/slashpath"
import "core:strings"

import "src:common"


If_Inversion_Context :: struct {
	if_stmt:          ^ast.If_Stmt,
	src:              string,
	base_indent:      string,
	control_flow_ctx: Control_Flow_Context,
	following_stmts:  []^ast.Stmt, // Statements after the if statement in the same block
	can_early_return: bool,
	strategy:         Inversion_Strategy,
}

Control_Flow_Context :: enum {
	Proc, // Use return
	For_Loop, // Use continue
}

Inversion_Strategy :: enum {
	Swap_Branches, // Has else, normal swap
	Unwrap_After_Control_Flow, // Has else, then ends with control flow
	Move_Following_Stmts, // No else, following stmts exist, body ends with control flow
	Insert_Early_Return, // No else, can early return
	Create_Empty_Branch, // No else, cannot early return
	Use_Or_Branch, // Pattern: if x, ok := expr; ok { ... } -> x := expr or_continue/or_return
}

Block_Text_Options :: struct {
	preserve_indent: bool, // Use original indentation
	target_indent:   string, // Target indentation (when not preserving)
	base_indent:     string, // Base indentation for the containing block (for else-if formatting)
	exclude_last:    bool, // Exclude the last statement
}

@(private = "package")
add_invert_if_action :: proc(
	doc_ctx: ^documents.Document,
	position: common.AbsolutePosition,
	uri: common.FileUri,
	actions: ^[dynamic]CodeAction,
) {
	inv_ctx := If_Inversion_Context {
		src = doc_ctx.syntaxTree.src,
	}

	if !find_if_stmt_at_position(&inv_ctx, doc_ctx.syntaxTree.decls[:], position) {
		return
	}

	new_text, ok := generate_inverted_if(&inv_ctx)
	if !ok {
		return
	}

	range: common.Range
	if should_edit_statements_after_if(inv_ctx) {
		last_stmt := inv_ctx.following_stmts[len(inv_ctx.following_stmts) - 1]
		range.start = common.token_pos_to_position(inv_ctx.if_stmt.pos, doc_ctx.syntaxTree.src)
		end_pos := last_stmt.end
		end_pos.offset -= 1
		range.end = common.token_pos_to_position(end_pos, doc_ctx.syntaxTree.src)
	} else {
		range = common.get_token_range(inv_ctx.if_stmt^, doc_ctx.syntaxTree.src)
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

should_edit_statements_after_if :: proc(inv_ctx: If_Inversion_Context) -> bool {
	// if there are statements after the if and the if body ends with control flow
	// we need to include those statements in the range since they will be moved
	// BUT only for Move_Following_Stmts strategy, not for Use_Or_Branch
	return(
		len(inv_ctx.following_stmts) > 0 &&
		body_ends_with_control_flow(inv_ctx.if_stmt.body) &&
		inv_ctx.if_stmt.else_stmt == nil &&
		inv_ctx.strategy != .Use_Or_Branch \
	)
}
// Find the innermost if statement that contains the given position
// This will NOT return else-if statements, only top-level if statements
// Also will not return an if statement if the position is in its else clause
// Populates the context with the if statement, control flow context, following statements, and early return capability
find_if_stmt_at_position :: proc(
	ctx: ^If_Inversion_Context,
	stmts: []^ast.Stmt,
	position: common.AbsolutePosition,
) -> bool {
	for stmt in stmts {
		if stmt == nil {
			continue
		}
		if find_if_stmt_in_node(ctx, stmt, position, false, .Proc, true) {
			return true
		}
	}
	return false
}

find_if_stmt_in_node :: proc(
	inv_ctx: ^If_Inversion_Context,
	node: ^ast.Node,
	position: common.AbsolutePosition,
	in_else_clause: bool,
	flow_ctx: Control_Flow_Context,
	is_last_in_parent: bool,
) -> bool {
	if node == nil {
		return false
	}

	if !(node.pos.offset <= position && position <= node.end.offset) {
		return false
	}

	#partial switch n in node.derived {
	case ^ast.If_Stmt:
		return handle_if_stmt_search(inv_ctx, n, position, in_else_clause, flow_ctx, is_last_in_parent)

	case ^ast.Block_Stmt:
		return search_block_stmts(inv_ctx, n.stmts, position, flow_ctx, is_last_in_parent)

	case ^ast.Proc_Lit:
		if n.body == nil do return false
		return find_if_stmt_in_node(inv_ctx, n.body, position, false, .Proc, true)

	case ^ast.Value_Decl:
		for value in n.values {
			if find_if_stmt_in_node(inv_ctx, value, position, false, flow_ctx, is_last_in_parent) {
				return true
			}
		}

	case ^ast.For_Stmt:
		if n.body == nil do return false
		return find_if_stmt_in_node(inv_ctx, n.body, position, false, .For_Loop, true)

	case ^ast.Range_Stmt:
		if n.body == nil do return false
		return find_if_stmt_in_node(inv_ctx, n.body, position, false, .For_Loop, true)

	case ^ast.Switch_Stmt:
		if n.body == nil do return false
		return find_if_stmt_in_node(inv_ctx, n.body, position, false, flow_ctx, is_last_in_parent)

	case ^ast.Type_Switch_Stmt:
		if n.body == nil do return false
		return find_if_stmt_in_node(inv_ctx, n.body, position, false, flow_ctx, is_last_in_parent)

	case ^ast.Case_Clause:
		return search_block_stmts(inv_ctx, n.body, position, flow_ctx, is_last_in_parent)

	case ^ast.When_Stmt:
		if n.body != nil {
			if find_if_stmt_in_node(inv_ctx, n.body, position, false, flow_ctx, is_last_in_parent) {
				return true
			}
		}
		if n.else_stmt != nil {
			if find_if_stmt_in_node(inv_ctx, n.else_stmt, position, false, flow_ctx, is_last_in_parent) {
				return true
			}
		}

	case ^ast.Defer_Stmt:
		if n.stmt == nil do return false
		return find_if_stmt_in_node(inv_ctx, n.stmt, position, false, flow_ctx, is_last_in_parent)
	}

	return false
}

handle_if_stmt_search :: proc(
	inv_ctx: ^If_Inversion_Context,
	n: ^ast.If_Stmt,
	position: common.AbsolutePosition,
	in_else_clause: bool,
	flow_ctx: Control_Flow_Context,
	is_last_in_parent: bool,
) -> bool {
	if n.else_stmt != nil && position_in_node(n.else_stmt, position) {
		if find_if_stmt_in_node(inv_ctx, n.else_stmt, position, true, flow_ctx, is_last_in_parent) {
			return true
		}
		return false
	}

	if n.body != nil && position_in_node(n.body, position) {
		// If we're inside the body of this if, we can early return if this if is last in its parent.
		// The else clause (if any) won't execute since we're in the body (then branch).
		if find_if_stmt_in_node(inv_ctx, n.body, position, false, flow_ctx, is_last_in_parent) {
			return true
		}
		return false
	}

	if in_else_clause {
		return false
	}

	inv_ctx.if_stmt = n
	inv_ctx.control_flow_ctx = flow_ctx
	inv_ctx.can_early_return = is_last_in_parent
	return true
}

search_block_stmts :: proc(
	inv_ctx: ^If_Inversion_Context,
	stmts: []^ast.Stmt,
	position: common.AbsolutePosition,
	flow_ctx: Control_Flow_Context,
	is_last_in_parent: bool,
) -> bool {
	for stmt, i in stmts {
		is_last := i == len(stmts) - 1
		if find_if_stmt_in_node(inv_ctx, stmt, position, false, flow_ctx, is_last && is_last_in_parent) {
			// Only update following_stmts and can_early_return if the found if statement
			// is directly in this block (not nested inside another statement)
			if inv_ctx.if_stmt != nil && cast(^ast.Node)inv_ctx.if_stmt == cast(^ast.Node)stmt {
				inv_ctx.following_stmts = stmts[i + 1:]
				inv_ctx.can_early_return = is_last && is_last_in_parent
			}
			return true
		}
	}
	return false
}

extract_node_text :: proc(src: string, node: ^ast.Node) -> string {
	if node == nil {
		return ""
	}
	return src[node.pos.offset:node.end.offset]
}

// Re-indent multi-line text from original_indent to target_indent
reindent_text :: proc(text: string, original_indent: string, target_indent: string) -> string {
	if original_indent == target_indent {
		return text
	}

	sb := strings.builder_make(context.temp_allocator)
	lines := strings.split_lines(text, context.temp_allocator)

	for line, i in lines {
		if i > 0 {
			strings.write_string(&sb, "\n")
		}

		// Check if line starts with original indent and replace it
		if strings.has_prefix(line, original_indent) {
			strings.write_string(&sb, target_indent)
			strings.write_string(&sb, line[len(original_indent):])
		} else {
			// Line has different indentation (possibly less), try to adjust relatively
			strings.write_string(&sb, line)
		}
	}

	return strings.to_string(sb)
}

determine_strategy :: proc(
	if_stmt: ^ast.If_Stmt,
	following_stmts: []^ast.Stmt,
	can_early_return: bool,
	control_flow_ctx: Control_Flow_Context,
) -> Inversion_Strategy {
	has_else := if_stmt.else_stmt != nil
	body_has_control_flow := body_ends_with_control_flow(if_stmt.body)
	has_following := len(following_stmts) > 0

	if has_else {
		if body_has_control_flow {
			return .Unwrap_After_Control_Flow
		}
		return .Swap_Branches
	}

	// Check for the or_continue/or_return pattern: if x, ok := expr; ok { ... }
	if can_use_or_branch(if_stmt, control_flow_ctx, can_early_return) {
		return .Use_Or_Branch
	}

	if body_has_control_flow && has_following {
		return .Move_Following_Stmts
	}

	if can_early_return {
		return .Insert_Early_Return
	}

	return .Create_Empty_Branch
}

// Check if the if statement matches the pattern: if x, ok := expr; ok { ... }
// which can be converted to: x := expr or_continue (in loop) or x := expr or_return (in proc)
can_use_or_branch :: proc(
	if_stmt: ^ast.If_Stmt,
	control_flow_ctx: Control_Flow_Context,
	can_early_return: bool,
) -> bool {
	// Must have init statement and no else clause
	if if_stmt.init == nil || if_stmt.else_stmt != nil {
		return false
	}

	// For loops: always can use or_continue
	// For procs: only if can_early_return (meaning the if is last in its block)
	if control_flow_ctx == .Proc && !can_early_return {
		return false
	}

	// The init must be a value declaration
	value_decl, ok := if_stmt.init.derived.(^ast.Value_Decl)
	if !ok {
		return false
	}

	// Must have exactly 2 names (e.g., symbol, ok)
	if len(value_decl.names) != 2 {
		return false
	}

	// The condition must be a simple identifier
	cond_ident, cond_ok := if_stmt.cond.derived.(^ast.Ident)
	if !cond_ok {
		return false
	}

	// The second name in the declaration must match the condition
	second_name, name_ok := value_decl.names[1].derived.(^ast.Ident)
	if !name_ok {
		return false
	}

	// Check if the condition identifier matches the second declaration name (the "ok" variable)
	return cond_ident.name == second_name.name
}

// Generate or_continue/or_return transformation
// Transforms: if symbol, ok := expr; ok { body }
// To: symbol := expr or_continue \n body
generate_or_branch :: proc(sb: ^strings.Builder, ctx: ^If_Inversion_Context) -> (string, bool) {
	value_decl := ctx.if_stmt.init.derived.(^ast.Value_Decl)

	// Get the first name (the actual value, not the ok)
	first_name, ok := value_decl.names[0].derived.(^ast.Ident)
	if !ok {
		return "", false
	}

	// Get the expression being assigned
	if len(value_decl.values) == 0 {
		return "", false
	}
	expr_text := extract_node_text(ctx.src, value_decl.values[0])

	// Determine which or_* to use
	or_branch := ctx.control_flow_ctx == .For_Loop ? "or_continue" : "or_return"

	// Write: name := expr or_continue
	strings.write_string(sb, first_name.name)
	strings.write_string(sb, " := ")
	strings.write_string(sb, expr_text)
	strings.write_string(sb, " ")
	strings.write_string(sb, or_branch)
	strings.write_string(sb, "\n")

	// Write the body statements at the base indent level
	then_body_text := get_block_body_text_at_indent(ctx.src, ctx.if_stmt.body, ctx.base_indent)
	then_body_text = strings.trim_right(then_body_text, "\n")
	strings.write_string(sb, then_body_text)

	return strings.to_string(sb^), true
}

// Write the if statement header (label, init, condition)
write_if_header :: proc(sb: ^strings.Builder, ctx: ^If_Inversion_Context) -> bool {
	if ctx.if_stmt.label != nil {
		label_text := extract_node_text(ctx.src, ctx.if_stmt.label)
		strings.write_string(sb, label_text)
		strings.write_string(sb, ": ")
	}

	strings.write_string(sb, "if ")

	if ctx.if_stmt.init != nil {
		init_text := extract_node_text(ctx.src, ctx.if_stmt.init)
		strings.write_string(sb, init_text)
		strings.write_string(sb, "; ")
	}

	if ctx.if_stmt.cond != nil {
		inverted_cond, ok := invert_condition(ctx.src, ctx.if_stmt.cond)
		if !ok {
			return false
		}
		strings.write_string(sb, inverted_cond)
	}

	strings.write_string(sb, " ")
	return true
}

// Strategy: Standard swap of if/else branches
generate_swap_branches :: proc(sb: ^strings.Builder, ctx: ^If_Inversion_Context) {
	else_body_text := get_block_body_text(ctx.src, ctx.if_stmt.else_stmt, ctx.base_indent)
	then_body_text := get_block_body_text(ctx.src, ctx.if_stmt.body, ctx.base_indent)

	strings.write_string(sb, "{\n")
	strings.write_string(sb, else_body_text)
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "} else {\n")
	strings.write_string(sb, then_body_text)
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "}")
}

// Strategy: Unwrap then-body after control flow (removes redundant else)
generate_unwrap_optimization :: proc(sb: ^strings.Builder, ctx: ^If_Inversion_Context) {
	else_body_text := get_block_body_text(ctx.src, ctx.if_stmt.else_stmt, ctx.base_indent)
	then_body_text := get_block_body_text_at_indent(ctx.src, ctx.if_stmt.body, ctx.base_indent)
	then_body_text = strings.trim_right(then_body_text, "\n")

	strings.write_string(sb, "{\n")
	strings.write_string(sb, else_body_text)
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "}\n")
	strings.write_string(sb, then_body_text)
}

// Strategy: Move following statements into if body
generate_move_following_stmts :: proc(sb: ^strings.Builder, ctx: ^If_Inversion_Context) {
	then_body_without_control := get_block_body_without_last_stmt_at_indent(ctx.src, ctx.if_stmt.body, ctx.base_indent)
	then_body_without_control = strings.trim_right(then_body_without_control, "\n")

	control_flow_text := get_last_stmt_text(ctx.src, ctx.if_stmt.body, ctx.base_indent)

	strings.write_string(sb, "{\n")
	for s in ctx.following_stmts {
		if s == nil do continue
		stmt_text := extract_node_text(ctx.src, s)
		strings.write_string(sb, ctx.base_indent)
		strings.write_string(sb, "\t")
		strings.write_string(sb, stmt_text)
		strings.write_string(sb, "\n")
	}
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "\t")
	strings.write_string(sb, control_flow_text)
	strings.write_string(sb, "\n")
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "}\n")
	strings.write_string(sb, then_body_without_control)
}

// Strategy: Insert early return/continue
generate_early_return :: proc(sb: ^strings.Builder, ctx: ^If_Inversion_Context) {
	then_body_text := get_block_body_text_at_indent(ctx.src, ctx.if_stmt.body, ctx.base_indent)
	then_body_text = strings.trim_right(then_body_text, "\n")

	control_flow_stmt := ctx.control_flow_ctx == .For_Loop ? "continue" : "return"

	strings.write_string(sb, "{\n")
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "\t")
	strings.write_string(sb, control_flow_stmt)
	strings.write_string(sb, "\n")
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "}\n")
	strings.write_string(sb, then_body_text)
}

// Strategy: Create empty if branch with else
generate_empty_branch :: proc(sb: ^strings.Builder, ctx: ^If_Inversion_Context) {
	then_body_text := get_block_body_text(ctx.src, ctx.if_stmt.body, ctx.base_indent)

	strings.write_string(sb, "{\n")
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "} else {\n")
	strings.write_string(sb, then_body_text)
	strings.write_string(sb, ctx.base_indent)
	strings.write_string(sb, "}")
}

generate_inverted_if :: proc(inv_ctx: ^If_Inversion_Context) -> (string, bool) {
	inv_ctx.base_indent = get_line_indentation(inv_ctx.src, inv_ctx.if_stmt.pos.offset)
	inv_ctx.strategy = determine_strategy(
		inv_ctx.if_stmt,
		inv_ctx.following_stmts,
		inv_ctx.can_early_return,
		inv_ctx.control_flow_ctx,
	)

	sb := strings.builder_make(context.temp_allocator)

	// For or_branch strategy, we generate completely different output
	if inv_ctx.strategy == .Use_Or_Branch {
		return generate_or_branch(&sb, inv_ctx)
	}

	if !write_if_header(&sb, inv_ctx) {
		return "", false
	}

	switch inv_ctx.strategy {
	case .Swap_Branches:
		generate_swap_branches(&sb, inv_ctx)
	case .Unwrap_After_Control_Flow:
		generate_unwrap_optimization(&sb, inv_ctx)
	case .Move_Following_Stmts:
		generate_move_following_stmts(&sb, inv_ctx)
	case .Insert_Early_Return:
		generate_early_return(&sb, inv_ctx)
	case .Create_Empty_Branch:
		generate_empty_branch(&sb, inv_ctx)
	case .Use_Or_Branch:
	// Already handled above
	}

	return strings.to_string(sb), true
}

// Unified text extraction from block statements
extract_block_text :: proc(src: string, stmt: ^ast.Stmt, options: Block_Text_Options) -> string {
	if stmt == nil {
		return ""
	}

	#partial switch block in stmt.derived {
	case ^ast.Block_Stmt:
		if len(block.stmts) == 0 {
			return ""
		}

		stmts_to_process := block.stmts
		if options.exclude_last && len(stmts_to_process) > 0 {
			stmts_to_process = stmts_to_process[:len(stmts_to_process) - 1]
		}

		if len(stmts_to_process) == 0 {
			return ""
		}

		sb := strings.builder_make(context.temp_allocator)

		for s in stmts_to_process {
			if s == nil do continue

			original_indent := get_line_indentation(src, s.pos.offset)
			target_indent := options.preserve_indent ? original_indent : options.target_indent
			stmt_text := extract_node_text(src, s)

			// Re-indent multi-line statements
			if !options.preserve_indent && original_indent != target_indent {
				stmt_text = reindent_text(stmt_text, original_indent, target_indent)
			}

			strings.write_string(&sb, target_indent)
			strings.write_string(&sb, stmt_text)
			strings.write_string(&sb, "\n")
		}

		return strings.to_string(sb)

	case ^ast.If_Stmt:
		// This is an else-if, need to handle it recursively
		// Use base_indent which is the indent level of the containing block
		if_text, ok := generate_inverted_if_for_else(src, block, options.base_indent)
		if ok {
			return if_text
		}
	}

	// Fallback: just return the statement text
	indent := options.preserve_indent ? "" : options.target_indent
	stmt_text := extract_node_text(src, stmt)
	return fmt.tprintf("%s%s\n", indent, stmt_text)
}

// Extract the body text from a block statement (without the braces) - DEPRECATED, use extract_block_text
get_block_body_text :: proc(src: string, stmt: ^ast.Stmt, base_indent: string) -> string {
	return extract_block_text(src, stmt, Block_Text_Options{preserve_indent = true, base_indent = base_indent})
}

// Extract the body text at a specific indentation level (for unwrapping) - DEPRECATED, use extract_block_text
get_block_body_text_at_indent :: proc(src: string, stmt: ^ast.Stmt, target_indent: string) -> string {
	return extract_block_text(
		src,
		stmt,
		Block_Text_Options{target_indent = target_indent, base_indent = target_indent},
	)
}

// Extract the body text at a specific indentation level, excluding the last statement - DEPRECATED, use extract_block_text
get_block_body_without_last_stmt_at_indent :: proc(src: string, stmt: ^ast.Stmt, target_indent: string) -> string {
	return extract_block_text(
		src,
		stmt,
		Block_Text_Options{target_indent = target_indent, base_indent = target_indent, exclude_last = true},
	)
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
// For else-if chains, preserve structure (don't invert) but re-indent
format_else_if_chain :: proc(
	src: string,
	if_stmt: ^ast.If_Stmt,
	base_indent: string,
	is_inline: bool,
) -> (
	string,
	bool,
) {
	sb := strings.builder_make(context.temp_allocator)

	// Write leading indent only if not inline (inline follows "} else ")
	if !is_inline {
		strings.write_string(&sb, base_indent)
		strings.write_string(&sb, "\t")
	}

	// Write "if <cond> {"
	strings.write_string(&sb, "if ")

	if if_stmt.init != nil {
		init_text := extract_node_text(src, if_stmt.init)
		strings.write_string(&sb, init_text)
		strings.write_string(&sb, "; ")
	}

	if if_stmt.cond != nil {
		cond_text := extract_node_text(src, if_stmt.cond)
		strings.write_string(&sb, cond_text)
	}

	strings.write_string(&sb, " {\n")

	// Write the body with increased indentation
	body_indent := is_inline ? base_indent : strings.concatenate({base_indent, "\t"}, context.temp_allocator)
	if if_stmt.body != nil {
		nested_indent := strings.concatenate({body_indent, "\t"}, context.temp_allocator)
		body_text := extract_block_text(src, if_stmt.body, Block_Text_Options{target_indent = nested_indent})
		strings.write_string(&sb, body_text)
	}

	strings.write_string(&sb, body_indent)

	// Handle else/else-if
	if if_stmt.else_stmt != nil {
		#partial switch else_block in if_stmt.else_stmt.derived {
		case ^ast.If_Stmt:
			// else-if: recursively handle
			strings.write_string(&sb, "} else ")
			else_if_text, ok := format_else_if_chain(src, else_block, body_indent, true)
			if !ok {
				return "", false
			}
			strings.write_string(&sb, else_if_text)
		case ^ast.Block_Stmt:
			// else block
			strings.write_string(&sb, "} else {\n")
			nested_indent := strings.concatenate({body_indent, "\t"}, context.temp_allocator)
			else_text := extract_block_text(src, if_stmt.else_stmt, Block_Text_Options{target_indent = nested_indent})
			strings.write_string(&sb, else_text)
			strings.write_string(&sb, body_indent)
			strings.write_string(&sb, "}\n")
		}
	} else {
		strings.write_string(&sb, "}\n")
	}

	return strings.to_string(sb), true
}

// DEPRECATED: Use format_else_if_chain with is_inline=false
generate_inverted_if_for_else :: proc(src: string, if_stmt: ^ast.If_Stmt, base_indent: string) -> (string, bool) {
	return format_else_if_chain(src, if_stmt, base_indent, false)
}

// DEPRECATED: Use format_else_if_chain with is_inline=true
generate_inverted_if_for_else_inline :: proc(
	src: string,
	if_stmt: ^ast.If_Stmt,
	base_indent: string,
) -> (
	string,
	bool,
) {
	return format_else_if_chain(src, if_stmt, base_indent, true)
}

// Get block body text with specific indentation (re-indenting) - DEPRECATED, use extract_block_text
get_block_body_text_reindented :: proc(src: string, stmt: ^ast.Stmt, target_indent: string) -> string {
	return extract_block_text(
		src,
		stmt,
		Block_Text_Options{target_indent = target_indent, base_indent = target_indent},
	)
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
