#+feature dynamic-literals
package analysis

import "core:odin/ast"
import "core:odin/parser"
import "src:codeprint"

GlobalFlags :: enum {
	Mutable,
	Variable,
}

GlobalExpr :: struct {
	name:       string,
	name_expr:  ^ast.Expr,
	expr:       ^ast.Expr,
	type_expr:  ^ast.Expr,
	value_expr: ^ast.Expr,
	flags:      bit_set[GlobalFlags],
	docs:       ^ast.Comment_Group,
	comment:    ^ast.Comment_Group,
	attributes: []^ast.Attribute,
	deprecated: bool,
	private:    parser.Private_Flag,
	builtin:    bool,
}

@(private)
collect_value_decl :: proc(
	exprs: ^[dynamic]GlobalExpr,
	file: ast.File,
	file_tags: parser.File_Tags,
	stmt: ^ast.Node,
	foreign_attrs: []^ast.Attribute,
) {
	value_decl, is_value_decl := stmt.derived.(^ast.Value_Decl)

	if !is_value_decl {
		return
	}
	comment, _ := get_file_comment(file, value_decl.pos.line)

	attributes := merge_attributes(value_decl.attributes[:], foreign_attrs)

	global_expr := GlobalExpr {
		docs       = value_decl.docs,
		comment    = comment,
		attributes = attributes,
		private    = file_tags.private,
	}

	if value_decl.is_mutable {
		global_expr.flags += {.Mutable}
	}

	for attribute in attributes {
		for elem in attribute.elems {
			ident, value, ok := unwrap_attr_elem(elem)
			if !ok {
				continue
			}

			switch ident.name {
			case "deprecated":
				global_expr.deprecated = true
			case "builtin":
				global_expr.builtin = true
			case "private":
				if value == nil {
					global_expr.private = .Package
				} else if val, ok := value.derived.(^ast.Basic_Lit); ok {
					switch val.tok.text {
					case "\"file\"":
						global_expr.private = .File
					case "\"package\"":
						global_expr.private = .Package
					}
				} else {
					global_expr.private = .Package
				}
			}
		}
	}

	if file_tags.ignore {
		global_expr.private = .File
	}

	for name, i in value_decl.names {
		global_expr.name = codeprint.get_ast_node_string(name, file.src)
		global_expr.name_expr = name

		if len(value_decl.values) > i {
			global_expr.value_expr = value_decl.values[i]
			if is_variable_declaration(value_decl.values[i]) {
				global_expr.flags += {.Variable}
			}
		}
		if value_decl.type != nil {
			global_expr.expr = value_decl.type
			global_expr.type_expr = value_decl.type
			append(exprs, global_expr)
		} else if len(value_decl.values) > i {
			global_expr.expr = value_decl.values[i]
			append(exprs, global_expr)
		}
	}
}

@(private)
collect_when_stmt :: proc(
	exprs: ^[dynamic]GlobalExpr,
	file: ast.File,
	file_tags: parser.File_Tags,
	when_decl: ^ast.When_Stmt,
) {
	if when_decl.cond == nil {
		return
	}

	if when_decl.body == nil {
		return
	}
	if stmt, ok := get_when_block_stmt(when_decl); ok {
		collect_when_body(exprs, file, file_tags, stmt)
	}
}

get_when_block_stmt :: proc(when_decl: ^ast.When_Stmt) -> (^ast.Block_Stmt, bool) {
	if resolve_when_condition(when_decl.cond) {
		if block, ok := when_decl.body.derived.(^ast.Block_Stmt); ok {
			return block, true
		}
	} else {
		else_stmt := when_decl.else_stmt

		for else_stmt != nil {
			if else_when, ok := else_stmt.derived.(^ast.When_Stmt); ok {
				if resolve_when_condition(else_when.cond) {
					if block, ok := else_when.body.derived.(^ast.Block_Stmt); ok {
						return block, true
					}
				}
				else_stmt = else_when.else_stmt
			} else {
				if block, ok := else_stmt.derived.(^ast.Block_Stmt); ok {
					return block, true
				}
				return nil, false
			}
		}
	}
	return nil, false
}

@(private)
collect_when_body :: proc(
	exprs: ^[dynamic]GlobalExpr,
	file: ast.File,
	file_tags: parser.File_Tags,
	block: ^ast.Block_Stmt,
) {
	for stmt in block.stmts {
		if when_stmt, ok := stmt.derived.(^ast.When_Stmt); ok {
			collect_when_stmt(exprs, file, file_tags, when_stmt)
		} else if foreign_decl, ok := stmt.derived.(^ast.Foreign_Block_Decl); ok {
			if foreign_decl.body != nil {
				if foreign_block, ok := foreign_decl.body.derived.(^ast.Block_Stmt); ok {
					for foreign_stmt in foreign_block.stmts {
						collect_value_decl(exprs, file, file_tags, foreign_stmt, foreign_decl.attributes[:])
					}
				}
			}
		} else {
			collect_value_decl(exprs, file, file_tags, stmt, {})
		}
	}
}

collect_globals :: proc(file: ast.File) -> []GlobalExpr {
	file_tags := parser.parse_file_tags(file, context.temp_allocator)
	if !should_collect_file(file_tags) {
		return {}
	}
	exprs := make([dynamic]GlobalExpr, context.temp_allocator)
	defer shrink(&exprs)

	for decl in file.decls {
		if value_decl, ok := decl.derived.(^ast.Value_Decl); ok {
			collect_value_decl(&exprs, file, file_tags, decl, {})
		} else if when_decl, ok := decl.derived.(^ast.When_Stmt); ok {
			collect_when_stmt(&exprs, file, file_tags, when_decl)
		} else if foreign_decl, ok := decl.derived.(^ast.Foreign_Block_Decl); ok {
			if foreign_decl.body == nil {
				continue
			}

			if block, ok := foreign_decl.body.derived.(^ast.Block_Stmt); ok {
				for stmt in block.stmts {
					collect_value_decl(&exprs, file, file_tags, stmt, foreign_decl.attributes[:])
				}
			}
		}
	}

	return exprs[:]
}
