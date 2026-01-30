package server

import "core:odin/ast"

import "src:common"

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
