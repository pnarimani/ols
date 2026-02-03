#+feature using-stmt
package analysis

import "base:intrinsics"

import "core:mem"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:reflect"
import "core:strings"

new_type :: proc($T: typeid, pos, end: tokenizer.Pos, allocator := context.allocator) -> ^T {
	n := new(T, allocator)
	n.pos = pos
	n.end = end
	n.derived = n
	base: ^ast.Node = n
	_ = base
	when intrinsics.type_has_field(T, "derived_expr") {
		n.derived_expr = n
	}
	when intrinsics.type_has_field(T, "derived_stmt") {
		n.derived_stmt = n
	}
	return n
}

clone_type :: proc {
	clone_node,
	clone_expr,
	clone_array,
	clone_dynamic_array,
	clone_comment_group,
}

clone_array :: proc(array: $A/[]^$T, allocator := context.allocator) -> A {
	if len(array) == 0 {
		return nil
	}
	res := make(A, len(array), allocator)
	for elem, i in array {
		res[i] = cast(^T)clone_type(elem, allocator)
	}
	return res
}

clone_dynamic_array :: proc(array: $A/[dynamic]^$T, allocator := context.allocator) -> A {
	if len(array) == 0 {
		return nil
	}
	res := make(A, len(array), allocator)
	for elem, i in array {
		res[i] = auto_cast clone_type(elem, allocator)
	}
	return res
}

clone_expr :: proc(node: ^ast.Expr, allocator := context.allocator) -> ^ast.Expr {
	return cast(^ast.Expr)clone_node(node, allocator)
}

clone_node :: proc(node: ^ast.Node, allocator := context.allocator) -> ^ast.Node {
	using ast
	if node == nil {
		return nil
	}

	size := size_of(Node)
	align := align_of(Node)
	ti := reflect.union_variant_type_info(node.derived)
	if ti != nil {
		elem := ti.variant.(reflect.Type_Info_Pointer).elem
		size = elem.size
		align = elem.align
	}

	#partial switch _ in node.derived {
	case ^Package, ^File:
		panic("Cannot clone this node type")
	}

	res := cast(^Node)(mem.alloc(size, align, allocator) or_else panic("OOM"))
	src: rawptr = node
	if node.derived != nil {
		src = (^rawptr)(&node.derived)^
	}
	mem.copy(res, src, size)
	res_ptr_any: any
	res_ptr_any.data = &res
	res_ptr_any.id = ti.id

	res.pos.file = get_interned_string(node.pos.file)
	res.end.file = get_interned_string(node.end.file)

	reflect.set_union_value(res.derived, res_ptr_any)

	if res.derived != nil do #partial switch r in res.derived {
	case ^Ident:
		n := node.derived.(^Ident)
		r.name = get_interned_string(n.name)
	case ^Implicit:
		n := node.derived.(^Implicit)
		r.tok.text = get_interned_string(n.tok.text)
	case ^Undef:
	case ^Basic_Lit:
		n := node.derived.(^Basic_Lit)
		r.tok.text = get_interned_string(n.tok.text)
	case ^Basic_Directive:
		n := node.derived.(^Basic_Directive)
		r.name = get_interned_string(n.name)
	case ^Ellipsis:
		r.expr = clone_type(r.expr, allocator)
	case ^Tag_Expr:
		r.expr = clone_type(r.expr, allocator)
	case ^Unary_Expr:
		n := node.derived.(^Unary_Expr)
		r.expr = clone_type(r.expr, allocator)
		r.op.text = get_interned_string(n.op.text)
	case ^Binary_Expr:
		n := node.derived.(^Binary_Expr)
		r.left = clone_type(r.left, allocator)
		r.right = clone_type(r.right, allocator)
		r.op.text = get_interned_string(n.op.text)
	case ^Paren_Expr:
		r.expr = clone_type(r.expr, allocator)
	case ^Selector_Expr:
		r.expr = clone_type(r.expr, allocator)
		r.field = auto_cast clone_type(r.field, allocator)
	case ^Selector_Call_Expr:
		r.expr = clone_type(r.expr, allocator)
		r.call = auto_cast clone_type(r.call, allocator)
	case ^Implicit_Selector_Expr:
		r.field = auto_cast clone_type(r.field, allocator)
	case ^Slice_Expr:
		r.expr = clone_type(r.expr, allocator)
		r.low = clone_type(r.low, allocator)
		r.high = clone_type(r.high, allocator)
	case ^Attribute:
		r.elems = clone_type(r.elems, allocator)
	case ^Distinct_Type:
		r.type = clone_type(r.type, allocator)
	case ^Proc_Type:
		r.params = auto_cast clone_type(r.params, allocator)
		r.results = auto_cast clone_type(r.results, allocator)
		r.calling_convention = clone_calling_convention(r.calling_convention)
	case ^Pointer_Type:
		r.tag = clone_type(r.tag, allocator)
		r.elem = clone_type(r.elem, allocator)
	case ^Array_Type:
		r.len = clone_type(r.len, allocator)
		r.elem = clone_type(r.elem, allocator)
		r.tag = clone_type(r.tag, allocator)
	case ^Dynamic_Array_Type:
		r.elem = clone_type(r.elem, allocator)
		r.tag = clone_type(r.tag, allocator)
	case ^Struct_Type:
		r.poly_params = auto_cast clone_type(r.poly_params, allocator)
		r.align = clone_type(r.align, allocator)
		r.fields = auto_cast clone_type(r.fields, allocator)
		r.where_clauses = clone_type(r.where_clauses, allocator)
		r.align = clone_type(r.align, allocator)
		r.max_field_align = clone_type(r.max_field_align, allocator)
		r.min_field_align = clone_type(r.min_field_align, allocator)
	case ^Field:
		r.names = clone_type(r.names, allocator)
		r.type = clone_type(r.type, allocator)
		r.default_value = clone_type(r.default_value, allocator)
		r.docs = clone_type(r.docs, allocator)
		r.comment = clone_type(r.comment, allocator)
	case ^Field_List:
		r.list = clone_type(r.list, allocator)
	case ^Field_Value:
		r.field = clone_type(r.field, allocator)
		r.value = clone_type(r.value, allocator)
	case ^Union_Type:
		r.poly_params = auto_cast clone_type(r.poly_params, allocator)
		r.align = clone_type(r.align, allocator)
		r.variants = clone_type(r.variants, allocator)
		r.where_clauses = clone_type(r.where_clauses, allocator)
	case ^Enum_Type:
		r.base_type = clone_type(r.base_type, allocator)
		r.fields = clone_type(r.fields, allocator)
	case ^Bit_Set_Type:
		r.elem = clone_type(r.elem, allocator)
		r.underlying = clone_type(r.underlying, allocator)
	case ^Map_Type:
		r.key = clone_type(r.key, allocator)
		r.value = clone_type(r.value, allocator)
	case ^Call_Expr:
		r.expr = clone_type(r.expr, allocator)
		r.args = clone_type(r.args, allocator)
	case ^Typeid_Type:
		r.specialization = clone_type(r.specialization, allocator)
	case ^Ternary_When_Expr:
		r.x = clone_type(r.x, allocator)
		r.cond = clone_type(r.cond, allocator)
		r.y = clone_type(r.y, allocator)
	case ^Ternary_If_Expr:
		r.x = clone_type(r.x, allocator)
		r.cond = clone_type(r.cond, allocator)
		r.y = clone_type(r.y, allocator)
	case ^Poly_Type:
		r.type = auto_cast clone_type(r.type, allocator)
		r.specialization = clone_type(r.specialization, allocator)
	case ^Proc_Group:
		r.args = clone_type(r.args, allocator)
	case ^Comp_Lit:
		r.type = clone_type(r.type, allocator)
		r.elems = clone_type(r.elems, allocator)
	case ^Proc_Lit:
		r.type = cast(^Proc_Type)clone_type(cast(^Node)r.type, allocator)
		r.body = nil
		r.where_clauses = clone_type(r.where_clauses, allocator)
	case ^Helper_Type:
		r.type = clone_type(r.type, allocator)
	case ^Type_Cast:
		r.type = clone_type(r.type, allocator)
		r.expr = clone_type(r.expr, allocator)
	case ^Deref_Expr:
		r.expr = clone_type(r.expr, allocator)
	case ^Index_Expr:
		r.expr = clone_type(r.expr, allocator)
		r.index = clone_type(r.index, allocator)
	case ^Multi_Pointer_Type:
		r.elem = clone_type(r.elem, allocator)
	case ^Matrix_Type:
		r.elem = clone_type(r.elem, allocator)
		r.column_count = clone_type(r.column_count, allocator)
		r.row_count = clone_type(r.row_count, allocator)
	case ^Type_Assertion:
		r.expr = clone_type(r.expr, allocator)
		r.type = clone_type(r.type, allocator)
	case ^Relative_Type:
		r.tag = clone_type(r.tag, allocator)
		r.type = clone_type(r.type, allocator)
	case ^Bit_Field_Type:
		r.backing_type = clone_type(r.backing_type, allocator)
		r.fields = clone_type(r.fields, allocator)
	case ^Bit_Field_Field:
		r.name = clone_type(r.name, allocator)
		r.type = clone_type(r.type, allocator)
		r.bit_size = clone_type(r.bit_size, allocator)
		r.docs = clone_type(r.docs, allocator)
		r.comments = clone_type(r.comments, allocator)
	case ^Or_Else_Expr:
		r.x = clone_type(r.x, allocator)
		r.y = clone_type(r.y, allocator)
	case ^Or_Branch_Expr:
		r.expr = clone_type(r.expr, allocator)
		r.label = clone_type(r.label, allocator)
	case ^Comment_Group:
		list := make([dynamic]tokenizer.Token, 0, len(r.list), allocator)
		for t in r.list {
			append(&list, tokenizer.Token{text = strings.clone(t.text, allocator), kind = t.kind, pos = tokenizer.Pos{file = strings.clone(t.pos.file, allocator), offset = t.pos.offset, line = t.pos.line, column = t.pos.column}})
		}
		r.list = list[:]
	case ^Auto_Cast:
		r.expr = clone_type(r.expr, allocator)
	case ^Or_Return_Expr:
		r.expr = clone_type(r.expr, allocator)
	case ^Matrix_Index_Expr:
		r.expr = clone_type(r.expr, allocator)
		r.row_index = clone_type(r.row_index, allocator)
		r.column_index = clone_type(r.column_index, allocator)
	case:
	}

	return res
}

clone_comment_group :: proc(node: ^ast.Comment_Group, allocator := context.allocator) -> ^ast.Comment_Group {
	return cast(^ast.Comment_Group)clone_node(node, allocator)
}

clone_calling_convention :: proc(cc: ast.Proc_Calling_Convention) -> ast.Proc_Calling_Convention {
	if cc == nil {
		return nil
	}

	switch v in cc {
	case string:
		return get_interned_string(v)
	case ast.Proc_Calling_Convention_Extra:
		return v
	}
	return nil
}
