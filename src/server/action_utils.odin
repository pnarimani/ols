package server

import "core:odin/ast"

import "src:common"

// ============================================================================
// Workspace Edit Utilities
// ============================================================================

// Create a WorkspaceEdit with text edits for a single URI.
// This is the standard pattern used by all code actions.
make_workspace_edit :: proc(uri: string, edits: []TextEdit) -> WorkspaceEdit {
	edit: WorkspaceEdit
	edit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	edit.changes[uri] = edits
	return edit
}

// ============================================================================
// Indentation Utilities
// ============================================================================

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

// ============================================================================
// Procedure Finding Utilities
// ============================================================================

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
