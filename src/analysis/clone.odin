#+feature using-stmt
package analysis

import "base:intrinsics"

import "core:mem"
import "core:odin/ast"
import "core:odin/tokenizer"
import "core:reflect"
import "core:strings"

new_type :: proc($T: typeid, pos, end: tokenizer.Pos) -> ^T {
	n := new(T)
	n.pos = pos
	n.end = end
	n.derived = n
	base: ^ast.Node = n // dummy check
	_ = base // "Use" type to make -vet happy
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

clone_array :: proc(array: $A/[]^$T) -> A {
	if len(array) == 0 {
		return nil
	}
	res := make(A, len(array))
	for elem, i in array {
		res[i] = cast(^T)clone_type(elem)
	}
	return res
}

clone_dynamic_array :: proc(array: $A/[dynamic]^$T) -> A {
	if len(array) == 0 {
		return nil
	}
	res := make(A, len(array))
	for elem, i in array {
		res[i] = auto_cast clone_type(elem)
	}
	return res
}

clone_expr :: proc(node: ^ast.Expr) -> ^ast.Expr {
	return cast(^ast.Expr)clone_node(node)
}

clone_node :: proc(node: ^ast.Node) -> ^ast.Node {
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

	res := cast(^Node)(mem.alloc(size, align) or_else panic("OOM"))
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

	// NOTE: These are not needed as we don't actually use `derived_expr` or `derived_stmt` in the codebase
	//
	//res_ptr := reflect.deref(res_ptr_any)
	//
	//if de := reflect.struct_field_value_by_name(res_ptr, "derived_expr", true); de != nil {
	//	reflect.set_union_value(de, res_ptr_any)
	//}
	//if ds := reflect.struct_field_value_by_name(res_ptr, "derived_stmt", true); ds != nil {
	//	reflect.set_union_value(ds, res_ptr_any)
	//}

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
		r.expr = clone_type(r.expr)
	case ^Tag_Expr:
		r.expr = clone_type(r.expr)
	case ^Unary_Expr:
		n := node.derived.(^Unary_Expr)
		r.expr = clone_type(r.expr)
		r.op.text = get_interned_string(n.op.text)
	case ^Binary_Expr:
		n := node.derived.(^Binary_Expr)
		r.left = clone_type(r.left)
		r.right = clone_type(r.right)
		//Todo: Replace this with some constant table for opeator text
		r.op.text = get_interned_string(n.op.text)
	case ^Paren_Expr:
		r.expr = clone_type(r.expr)
	case ^Selector_Expr:
		r.expr = clone_type(r.expr)
		r.field = auto_cast clone_type(r.field)
	case ^Selector_Call_Expr:
		r.expr = clone_type(r.expr)
		r.call = auto_cast clone_type(r.call)
	case ^Implicit_Selector_Expr:
		r.field = auto_cast clone_type(r.field)
	case ^Slice_Expr:
		r.expr = clone_type(r.expr)
		r.low = clone_type(r.low)
		r.high = clone_type(r.high)
	case ^Attribute:
		r.elems = clone_type(r.elems)
	case ^Distinct_Type:
		r.type = clone_type(r.type)
	case ^Proc_Type:
		r.params = auto_cast clone_type(r.params)
		r.results = auto_cast clone_type(r.results)
		r.calling_convention = clone_calling_convention(r.calling_convention)
	case ^Pointer_Type:
		r.tag = clone_type(r.tag)
		r.elem = clone_type(r.elem)
	case ^Array_Type:
		r.len = clone_type(r.len)
		r.elem = clone_type(r.elem)
		r.tag = clone_type(r.tag)
	case ^Dynamic_Array_Type:
		r.elem = clone_type(r.elem)
		r.tag = clone_type(r.tag)
	case ^Struct_Type:
		r.poly_params = auto_cast clone_type(r.poly_params)
		r.align = clone_type(r.align)
		r.fields = auto_cast clone_type(r.fields)
		r.where_clauses = clone_type(r.where_clauses)
		r.align = clone_type(r.align)
		r.max_field_align = clone_type(r.max_field_align)
		r.min_field_align = clone_type(r.min_field_align)
	case ^Field:
		r.names = clone_type(r.names)
		r.type = clone_type(r.type)
		r.default_value = clone_type(r.default_value)
		r.docs = clone_type(r.docs)
		r.comment = clone_type(r.comment)
	case ^Field_List:
		r.list = clone_type(r.list)
	case ^Field_Value:
		r.field = clone_type(r.field)
		r.value = clone_type(r.value)
	case ^Union_Type:
		r.poly_params = auto_cast clone_type(r.poly_params)
		r.align = clone_type(r.align)
		r.variants = clone_type(r.variants)
		r.where_clauses = clone_type(r.where_clauses)
	case ^Enum_Type:
		r.base_type = clone_type(r.base_type)
		r.fields = clone_type(r.fields)
	case ^Bit_Set_Type:
		r.elem = clone_type(r.elem)
		r.underlying = clone_type(r.underlying)
	case ^Map_Type:
		r.key = clone_type(r.key)
		r.value = clone_type(r.value)
	case ^Call_Expr:
		r.expr = clone_type(r.expr)
		r.args = clone_type(r.args)
	case ^Typeid_Type:
		r.specialization = clone_type(r.specialization)
	case ^Ternary_When_Expr:
		r.x = clone_type(r.x)
		r.cond = clone_type(r.cond)
		r.y = clone_type(r.y)
	case ^Ternary_If_Expr:
		r.x = clone_type(r.x)
		r.cond = clone_type(r.cond)
		r.y = clone_type(r.y)
	case ^Poly_Type:
		r.type = auto_cast clone_type(r.type)
		r.specialization = clone_type(r.specialization)
	case ^Proc_Group:
		r.args = clone_type(r.args)
	case ^Comp_Lit:
		r.type = clone_type(r.type)
		r.elems = clone_type(r.elems)
	case ^Proc_Lit:
		r.type = cast(^Proc_Type)clone_type(cast(^Node)r.type)
		r.body = nil
		r.where_clauses = clone_type(r.where_clauses)
	case ^Helper_Type:
		r.type = clone_type(r.type)
	case ^Type_Cast:
		r.type = clone_type(r.type)
		r.expr = clone_type(r.expr)
	case ^Deref_Expr:
		r.expr = clone_type(r.expr)
	case ^Index_Expr:
		r.expr = clone_type(r.expr)
		r.index = clone_type(r.index)
	case ^Multi_Pointer_Type:
		r.elem = clone_type(r.elem)
	case ^Matrix_Type:
		r.elem = clone_type(r.elem)
		r.column_count = clone_type(r.column_count)
		r.row_count = clone_type(r.row_count)
	case ^Type_Assertion:
		r.expr = clone_type(r.expr)
		r.type = clone_type(r.type)
	case ^Relative_Type:
		r.tag = clone_type(r.tag)
		r.type = clone_type(r.type)
	case ^Bit_Field_Type:
		r.backing_type = clone_type(r.backing_type)
		r.fields = clone_type(r.fields)
	case ^Bit_Field_Field:
		r.name = clone_type(r.name)
		r.type = clone_type(r.type)
		r.bit_size = clone_type(r.bit_size)
		r.docs = clone_type(r.docs)
		r.comments = clone_type(r.comments)
	case ^Or_Else_Expr:
		r.x = clone_type(r.x)
		r.y = clone_type(r.y)
	case ^Or_Branch_Expr:
		r.expr = clone_type(r.expr)
		r.label = clone_type(r.label)
	case ^Comment_Group:
		list := make([dynamic]tokenizer.Token, 0, len(r.list))
		for t in r.list {
			append(&list, tokenizer.Token{text = strings.clone(t.text), kind = t.kind, pos = tokenizer.Pos{file = strings.clone(t.pos.file), offset = t.pos.offset, line = t.pos.line, column = t.pos.column}})
		}
		r.list = list[:]
	case ^Auto_Cast:
		r.expr = clone_type(r.expr)
	case ^Or_Return_Expr:
		r.expr = clone_type(r.expr)
	case ^Matrix_Index_Expr:
		r.expr = clone_type(r.expr)
		r.row_index = clone_type(r.row_index)
		r.column_index = clone_type(r.column_index)
	case:
	}

	return res
}

clone_comment_group :: proc(node: ^ast.Comment_Group) -> ^ast.Comment_Group {
	return cast(^ast.Comment_Group)clone_node(node)
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
