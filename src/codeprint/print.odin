#+feature dynamic-literals
#+feature using-stmt
package codeprint

import "core:odin/ast"
import path "core:path/slashpath"
import "core:strings"

/*
	Returns the string representation of a type. This allows us to print the signature without storing it in the indexer as a string(saving memory).
*/

node_to_string :: proc(node: ^ast.Node, remove_pointers := false) -> string {
	builder := strings.builder_make(context.temp_allocator)

	build_string(node, &builder, remove_pointers)

	return strings.to_string(builder)
}

build_string :: proc {
	build_string_ast_array,
	build_string_dynamic_array,
	build_string_node,
}

build_string_dynamic_array :: proc(array: $A/[]^$T, builder: ^strings.Builder, remove_pointers: bool) {
	for elem, i in array {
		build_string(elem, builder, remove_pointers)
	}
}

build_string_ast_array :: proc(array: $A/[dynamic]^$T, builder: ^strings.Builder, remove_pointers: bool) {
	for elem, i in array {
		build_string(elem, builder, remove_pointers)
	}
}

build_string_node :: proc(node: ^ast.Node, builder: ^strings.Builder, remove_pointers: bool) {
	using ast

	if node == nil {
		return
	}

	#partial switch n in node.derived {
	case ^Bad_Expr:
	case ^Ident:
		if strings.contains(n.name, "/") {
			strings.write_string(builder, path.base(n.name, false, context.temp_allocator))
		} else {
			strings.write_string(builder, n.name)
		}
	case ^Implicit:
		strings.write_string(builder, n.tok.text)
	case ^Undef:
	case ^Basic_Lit:
		strings.write_string(builder, n.tok.text)
	case ^Basic_Directive:
		strings.write_string(builder, "#")
		strings.write_string(builder, n.name)
	case ^Implicit_Selector_Expr:
		strings.write_string(builder, ".")
		build_string(n.field, builder, remove_pointers)
	case ^Ellipsis:
		strings.write_string(builder, "..")
		build_string(n.expr, builder, remove_pointers)
	case ^Proc_Lit:
		build_string(n.type, builder, remove_pointers)
		build_string(n.body, builder, remove_pointers)
	case ^Comp_Lit:
		build_string(n.type, builder, remove_pointers)
		strings.write_string(builder, "{")
		for elem, i in n.elems {
			build_string(elem, builder, remove_pointers)
			if len(n.elems) - 1 != i {
				strings.write_string(builder, ", ")
			}
		}
		strings.write_string(builder, "}")
	case ^Tag_Expr:
		build_string(n.expr, builder, remove_pointers)
	case ^Unary_Expr:
		strings.write_string(builder, n.op.text)
		build_string(n.expr, builder, remove_pointers)
	case ^Binary_Expr:
		build_string(n.left, builder, remove_pointers)
		strings.write_string(builder, " ")
		strings.write_string(builder, n.op.text)
		strings.write_string(builder, " ")
		build_string(n.right, builder, remove_pointers)
	case ^Paren_Expr:
		strings.write_string(builder, "(")
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, ")")
	case ^Call_Expr:
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, "(")
		for arg, i in n.args {
			build_string(arg, builder, remove_pointers)
			if len(n.args) - 1 != i {
				strings.write_string(builder, ", ")
			}
		}
		strings.write_string(builder, ")")
	case ^Selector_Expr:
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, ".")
		build_string(n.field, builder, remove_pointers)
	case ^Index_Expr:
		build_string(n.expr, builder, remove_pointers)
		strings.write_string(builder, "[")
		build_string(n.index, builder, remove_pointers)
		strings.write_string(builder, "]")
	case ^Deref_Expr:
		build_string(n.expr, builder, remove_pointers)
	case ^Slice_Expr:
		build_string(n.expr, builder, remove_pointers)
		build_string(n.low, builder, remove_pointers)
		build_string(n.high, builder, remove_pointers)
	case ^Field_Value:
		build_string(n.field, builder, remove_pointers)
		strings.write_string(builder, ": ")
		build_string(n.value, builder, remove_pointers)
	case ^Type_Cast:
		build_string(n.type, builder, remove_pointers)
		build_string(n.expr, builder, remove_pointers)
	case ^Bad_Stmt:
	case ^Bad_Decl:
	case ^Attribute:
		build_string(n.elems, builder, remove_pointers)
	case ^Field:
		for name, i in n.names {
			build_string(name, builder, remove_pointers)
			if len(n.names) - 1 != i {
				strings.write_string(builder, ", ")
			}
		}

		if len(n.names) > 0 && n.type != nil {
			strings.write_string(builder, ": ")
			build_string(n.type, builder, remove_pointers)

			if n.default_value != nil && n.type != nil {
				strings.write_string(builder, " = ")
			}

		} else if len(n.names) > 0 && n.default_value != nil {
			strings.write_string(builder, " := ")
		} else {
			build_string(n.type, builder, remove_pointers)
		}

		build_string(n.default_value, builder, remove_pointers)
	case ^Field_List:
		for field, i in n.list {
			build_string(field, builder, remove_pointers)
			if len(n.list) - 1 != i {
				strings.write_string(builder, ", ")
			}
		}
	case ^Typeid_Type:
		strings.write_string(builder, "typeid")
		if n.specialization != nil {
			strings.write_string(builder, "/")
			build_string(n.specialization, builder, remove_pointers)
		}
	case ^Helper_Type:
		build_string(n.type, builder, remove_pointers)
	case ^Distinct_Type:
		build_string(n.type, builder, remove_pointers)
	case ^Poly_Type:
		strings.write_string(builder, "$")

		build_string(n.type, builder, remove_pointers)

		if n.specialization != nil {
			strings.write_string(builder, "/")
			build_string(n.specialization, builder, remove_pointers)
		}
	case ^Proc_Type:
		strings.write_string(builder, "proc(")
		build_string(n.params, builder, remove_pointers)
		strings.write_string(builder, ")")
		if n.results != nil {
			strings.write_string(builder, " -> ")
			build_string(n.results, builder, remove_pointers)
		}
	case ^Pointer_Type:
		build_string(n.tag, builder, remove_pointers)
		if !remove_pointers {
			strings.write_string(builder, "^")
		}
		build_string(n.elem, builder, remove_pointers)
	case ^Array_Type:
		build_string(n.tag, builder, remove_pointers)
		strings.write_string(builder, "[")
		build_string(n.len, builder, remove_pointers)
		strings.write_string(builder, "]")
		build_string(n.elem, builder, remove_pointers)
	case ^Dynamic_Array_Type:
		build_string(n.tag, builder, remove_pointers)
		strings.write_string(builder, "[dynamic]")
		build_string(n.elem, builder, remove_pointers)
	case ^Struct_Type:
		strings.write_string(builder, "struct{")
		build_string(n.poly_params, builder, remove_pointers)
		build_string(n.align, builder, remove_pointers)
		build_string(n.fields, builder, remove_pointers)
		strings.write_string(builder, "}")
	case ^Union_Type:
		strings.write_string(builder, "union{")
		build_string(n.poly_params, builder, remove_pointers)
		build_string(n.align, builder, remove_pointers)
		for variant, i in n.variants {
			if i != 0 {
				strings.write_string(builder, ", ")
			}
			build_string(variant, builder, remove_pointers)
		}
		strings.write_string(builder, "}")
	case ^Enum_Type:
		strings.write_string(builder, "enum")
		build_string(n.base_type, builder, remove_pointers)
		strings.write_string(builder, "{")
		for field, i in n.fields {
			if i != 0 {
				strings.write_string(builder, ", ")
			}
			build_string(field, builder, remove_pointers)
		}
		strings.write_string(builder, "}")
	case ^Bit_Set_Type:
		strings.write_string(builder, "bit_set")
		strings.write_string(builder, "[")
		build_string(n.elem, builder, remove_pointers)
		if n.underlying != nil {
			strings.write_string(builder, "; ")
			build_string(n.underlying, builder, remove_pointers)
		}
		strings.write_string(builder, "]")
	case ^Map_Type:
		strings.write_string(builder, "map")
		strings.write_string(builder, "[")
		build_string(n.key, builder, remove_pointers)
		strings.write_string(builder, "]")
		build_string(n.value, builder, remove_pointers)
	case ^Matrix_Type:
		strings.write_string(builder, "matrix")
		strings.write_string(builder, "[")
		build_string(n.row_count, builder, remove_pointers)
		strings.write_string(builder, ",")
		build_string(n.column_count, builder, remove_pointers)
		strings.write_string(builder, "]")
		build_string(n.elem, builder, remove_pointers)
	case ^ast.Multi_Pointer_Type:
		strings.write_string(builder, "[^]")
		build_string(n.elem, builder, remove_pointers)
	case ^ast.Bit_Field_Type:
		strings.write_string(builder, "bit_field")
		build_string(n.backing_type, builder, remove_pointers)
		for field, i in n.fields {
			build_string(field, builder, remove_pointers)
			if len(n.fields) - 1 != i {
				strings.write_string(builder, ",")
			}
		}
	case ^ast.Bit_Field_Field:
		build_string(n.name, builder, remove_pointers)
		strings.write_string(builder, ": ")
		build_string(n.type, builder, remove_pointers)
		strings.write_string(builder, " | ")
		build_string(n.bit_size, builder, remove_pointers)
	}
}

repeat :: proc(value: string, count: int, allocator := context.allocator) -> string {
	if count <= 0 {
		return ""
	}
	return strings.repeat(value, count, allocator)
}

get_ast_node_string :: proc(node: ^ast.Node, src: string) -> string {
	return strings.trim_prefix(string(src[node.pos.offset:node.end.offset]), "$")
}
