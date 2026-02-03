#+feature using-stmt
package analysis

import "core:fmt"
import "core:mem"
import "core:odin/ast"

free_ast :: proc {
	free_ast_node,
	free_ast_array,
	free_ast_dynamic_array,
	free_ast_comment,
}

free_ast_comment :: proc(a: ^ast.Comment_Group, allocator: mem.Allocator) {
	if a == nil {
		return
	}

	if len(a.list) > 0 {
		delete(a.list, allocator)
	}

	free(a, allocator)
}

free_ast_array :: proc(array: $A/[]^$T, allocator: mem.Allocator) {
	for elem, i in array {
		free_ast(elem, allocator)
	}
	delete(array, allocator)
}

free_ast_dynamic_array :: proc(array: $A/[dynamic]^$T, allocator: mem.Allocator) {
	for elem, i in array {
		free_ast(elem, allocator)
	}

	delete(array)
}

free_ast_node :: proc(node: ^ast.Node, allocator: mem.Allocator) {
	using ast

	if node == nil {
		return
	}

	if node.derived != nil do #partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
	case ^Implicit:
	case ^Undef:
	case ^Basic_Directive:
	case ^Basic_Lit:
	case ^Ellipsis:
		free_ast(n.expr, allocator)
	case ^Proc_Lit:
		free_ast(n.type, allocator)
		free_ast(n.body, allocator)
		free_ast(n.where_clauses, allocator)
	case ^Comp_Lit:
		free_ast(n.type, allocator)
		free_ast(n.elems, allocator)
	case ^Tag_Expr:
		free_ast(n.expr, allocator)
	case ^Unary_Expr:
		free_ast(n.expr, allocator)
	case ^Binary_Expr:
		free_ast(n.left, allocator)
		free_ast(n.right, allocator)
	case ^Paren_Expr:
		free_ast(n.expr, allocator)
	case ^Call_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.args, allocator)
	case ^Selector_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.field, allocator)
	case ^Selector_Call_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.call, allocator)
	case ^Implicit_Selector_Expr:
		free_ast(n.field, allocator)
	case ^Index_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.index, allocator)
	case ^Deref_Expr:
		free_ast(n.expr, allocator)
	case ^Slice_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.low, allocator)
		free_ast(n.high, allocator)
	case ^Field_Value:
		free_ast(n.field, allocator)
		free_ast(n.value, allocator)
	case ^Ternary_If_Expr:
		free_ast(n.x, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.y, allocator)
	case ^Ternary_When_Expr:
		free_ast(n.x, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.y, allocator)
	case ^Type_Assertion:
		free_ast(n.expr, allocator)
		free_ast(n.type, allocator)
	case ^Type_Cast:
		free_ast(n.type, allocator)
		free_ast(n.expr, allocator)
	case ^Auto_Cast:
		free_ast(n.expr, allocator)
	case ^Bad_Stmt:
	case ^Empty_Stmt:
	case ^Expr_Stmt:
		free_ast(n.expr, allocator)
	case ^Tag_Stmt:
		r := cast(^Expr_Stmt)node
		free_ast(r.expr, allocator)
	case ^Assign_Stmt:
		free_ast(n.lhs, allocator)
		free_ast(n.rhs, allocator)
	case ^Block_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.stmts, allocator)
	case ^If_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.init, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.body, allocator)
		free_ast(n.else_stmt, allocator)
	case ^When_Stmt:
		free_ast(n.cond, allocator)
		free_ast(n.body, allocator)
		free_ast(n.else_stmt, allocator)
	case ^Return_Stmt:
		free_ast(n.results, allocator)
	case ^Defer_Stmt:
		free_ast(n.stmt, allocator)
	case ^For_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.init, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.post, allocator)
		free_ast(n.body, allocator)
	case ^Range_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.vals, allocator)
		free_ast(n.expr, allocator)
		free_ast(n.body, allocator)
	case ^Case_Clause:
		free_ast(n.list, allocator)
		free_ast(n.body, allocator)
	case ^Switch_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.init, allocator)
		free_ast(n.cond, allocator)
		free_ast(n.body, allocator)
	case ^Type_Switch_Stmt:
		free_ast(n.label, allocator)
		free_ast(n.tag, allocator)
		free_ast(n.expr, allocator)
		free_ast(n.body, allocator)
	case ^Branch_Stmt:
		free_ast(n.label, allocator)
	case ^Using_Stmt:
		free_ast(n.list, allocator)
	case ^Bad_Decl:
	case ^Value_Decl:
		free_ast(n.attributes, allocator)
		free_ast(n.names, allocator)
		free_ast(n.type, allocator)
		free_ast(n.values, allocator)
	case ^Package_Decl:
	case ^Import_Decl:
	case ^Foreign_Block_Decl:
		free_ast(n.attributes, allocator)
		free_ast(n.foreign_library, allocator)
		free_ast(n.body, allocator)
	case ^Foreign_Import_Decl:
		free_ast(n.name, allocator)
		free_ast(n.attributes, allocator)
	case ^Proc_Group:
		free_ast(n.args, allocator)
	case ^Attribute:
		free_ast(n.elems, allocator)
	case ^Field:
		free_ast(n.names, allocator)
		free_ast(n.type, allocator)
		free_ast(n.default_value, allocator)
		free_ast_comment(n.docs, allocator)
		free_ast_comment(n.comment, allocator)
	case ^Field_List:
		free_ast(n.list, allocator)
	case ^Typeid_Type:
		free_ast(n.specialization, allocator)
	case ^Helper_Type:
		free_ast(n.type, allocator)
	case ^Distinct_Type:
		free_ast(n.type, allocator)
	case ^Poly_Type:
		free_ast(n.type, allocator)
		free_ast(n.specialization, allocator)
	case ^Proc_Type:
		free_ast(n.params, allocator)
		free_ast(n.results, allocator)
	case ^Pointer_Type:
		free_ast(n.elem, allocator)
	case ^Array_Type:
		free_ast(n.len, allocator)
		free_ast(n.elem, allocator)
		free_ast(n.tag, allocator)
	case ^Dynamic_Array_Type:
		free_ast(n.elem, allocator)
		free_ast(n.tag, allocator)
	case ^Struct_Type:
		free_ast(n.poly_params, allocator)
		free_ast(n.align, allocator)
		free_ast(n.fields, allocator)
		free_ast(n.where_clauses, allocator)
	case ^Union_Type:
		free_ast(n.poly_params, allocator)
		free_ast(n.align, allocator)
		free_ast(n.variants, allocator)
		free_ast(n.where_clauses, allocator)
	case ^Enum_Type:
		free_ast(n.base_type, allocator)
		free_ast(n.fields, allocator)
	case ^Bit_Set_Type:
		free_ast(n.elem, allocator)
		free_ast(n.underlying, allocator)
	case ^Map_Type:
		free_ast(n.key, allocator)
		free_ast(n.value, allocator)
	case ^Multi_Pointer_Type:
		free_ast(n.elem, allocator)
	case ^Matrix_Type:
		free_ast(n.elem, allocator)
	case ^Relative_Type:
		free_ast(n.tag, allocator)
		free_ast(n.type, allocator)
	case ^Bit_Field_Type:
		free_ast(n.backing_type, allocator)
		for field in n.fields do free_ast(field, allocator)
	case ^Bit_Field_Field:
		free_ast(n.name, allocator)
		free_ast(n.type, allocator)
		free_ast(n.bit_size, allocator)
	case ^Or_Else_Expr:
		free_ast(n.x, allocator)
		free_ast(n.y, allocator)
	case ^Or_Return_Expr:
		free_ast(n.expr, allocator)
	case ^Or_Branch_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.label, allocator)
	case ^Matrix_Index_Expr:
		free_ast(n.expr, allocator)
		free_ast(n.row_index, allocator)
		free_ast(n.column_index, allocator)
	case:
		panic(fmt.aprintf("free Unhandled node kind: %v", node.derived))
	}

	mem.free(node, allocator)
}

free_ast_file :: proc(file: ast.File, allocator := context.allocator) {
	for decl in file.decls {
		free_ast(decl, allocator)
	}

	free_ast(file.pkg_decl, allocator)

	for comment in file.comments {
		free_ast(comment, allocator)
	}

	delete(file.comments)
	delete(file.imports)
	delete(file.decls)
}
