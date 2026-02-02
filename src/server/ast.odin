#+feature dynamic-literals
#+feature using-stmt
package server

import "src:analysis"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:strings"



node_equal :: proc {
	node_equal_node,
	node_equal_array,
	node_equal_dynamic_array,
}

node_equal_array :: proc(a, b: $A/[]^$T) -> bool {
	ret := true

	if len(a) != len(b) {
		return false
	}

	for elem, i in a {
		ret &= node_equal(elem, b[i])
	}

	return ret
}

node_equal_dynamic_array :: proc(a, b: $A/[dynamic]^$T) -> bool {
	ret := true

	if len(a) != len(b) {
		return false
	}

	for elem, i in a {
		ret &= node_equal(elem, b[i])
	}

	return ret
}

node_equal_node :: proc(a, b: ^ast.Node) -> bool {
	using ast

	if a == nil || b == nil {
		return false
	}

	#partial switch m in b.derived {
	case ^Bad_Expr:
		if n, ok := a.derived.(^Bad_Expr); ok {
			return true
		}
	case ^Ident:
		if n, ok := a.derived.(^Ident); ok {
			return true
			//return n.name == m.name;
		}
	case ^Implicit:
		if n, ok := a.derived.(^Implicit); ok {
			return true
		}
	case ^Undef:
		if n, ok := a.derived.(^Undef); ok {
			return true
		}
	case ^Basic_Lit:
		if n, ok := a.derived.(^Basic_Lit); ok {
			return true
		}
	case ^Poly_Type:
		return true
	case ^Ellipsis:
		if n, ok := a.derived.(^Ellipsis); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Tag_Expr:
		if n, ok := a.derived.(^Tag_Expr); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Unary_Expr:
		if n, ok := a.derived.(^Unary_Expr); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Binary_Expr:
		if n, ok := a.derived.(^Binary_Expr); ok {
			ret := node_equal(n.left, m.left)
			ret &= node_equal(n.right, m.right)
			return ret
		}
	case ^Paren_Expr:
		if n, ok := a.derived.(^Paren_Expr); ok {
			return node_equal(n.expr, m.expr)
		}
	case ^Selector_Expr:
		if n, ok := a.derived.(^Selector_Expr); ok {
			ret := node_equal(n.expr, m.expr)
			ret &= node_equal(n.field, m.field)
			return ret
		}
	case ^Slice_Expr:
		if n, ok := a.derived.(^Slice_Expr); ok {
			ret := node_equal(n.expr, m.expr)
			ret &= node_equal(n.low, m.low)
			ret &= node_equal(n.high, m.high)
			return ret
		}
	case ^Distinct_Type:
		if n, ok := a.derived.(^Distinct_Type); ok {
			return node_equal(n.type, m.type)
		}
	case ^Proc_Type:
		if n, ok := a.derived.(^Proc_Type); ok {
			ret := node_equal(n.params, m.params)
			ret &= node_equal(n.results, m.results)
			return ret
		}
	case ^Pointer_Type:
		if n, ok := a.derived.(^Pointer_Type); ok {
			return node_equal(n.elem, m.elem)
		}
	case ^Array_Type:
		if n, ok := a.derived.(^Array_Type); ok {
			ret := node_equal(n.elem, m.elem)
			if n.len != nil && m.len != nil {
				ret &= node_equal(n.len, m.len)
			}
			return ret
		}
	case ^Dynamic_Array_Type:
		if n, ok := a.derived.(^Dynamic_Array_Type); ok {
			return node_equal(n.elem, m.elem)
		}
	case ^ast.Multi_Pointer_Type:
		if n, ok := a.derived.(^Multi_Pointer_Type); ok {
			return node_equal(n.elem, m.elem)
		}
	case ^Struct_Type:
		if n, ok := a.derived.(^Struct_Type); ok {
			ret := node_equal(n.poly_params, m.poly_params)
			ret &= node_equal(n.align, m.align)
			ret &= node_equal(n.fields, m.fields)
			return ret
		}
	case ^Field:
		if n, ok := a.derived.(^Field); ok {
			ret := node_equal(n.names, m.names)
			ret &= node_equal(n.type, m.type)
			ret &= node_equal(n.default_value, m.default_value)
			return ret
		}
	case ^Field_List:
		if n, ok := a.derived.(^Field_List); ok {
			return node_equal(n.list, m.list)
		}
	case ^Field_Value:
		if n, ok := a.derived.(^Field_Value); ok {
			ret := node_equal(n.field, m.field)
			ret &= node_equal(n.value, m.value)
			return ret
		}
	case ^Union_Type:
		if n, ok := a.derived.(^Union_Type); ok {
			ret := node_equal(n.poly_params, m.poly_params)
			ret &= node_equal(n.align, m.align)
			ret &= node_equal(n.variants, m.variants)
			return ret
		}
	case ^Enum_Type:
		if n, ok := a.derived.(^Enum_Type); ok {
			ret := node_equal(n.base_type, m.base_type)
			ret &= node_equal(n.fields, m.fields)
			return ret
		}
	case ^Bit_Set_Type:
		if n, ok := a.derived.(^Bit_Set_Type); ok {
			ret := node_equal(n.elem, m.elem)
			ret &= node_equal(n.underlying, m.underlying)
			return ret
		}
	case ^Map_Type:
		if n, ok := a.derived.(^Map_Type); ok {
			ret := node_equal(n.key, m.key)
			ret &= node_equal(n.value, m.value)
			return ret
		}
	case ^Call_Expr:
		if n, ok := a.derived.(^Call_Expr); ok {
			ret := node_equal(n.expr, m.expr)
			ret &= node_equal(n.args, m.args)
			return ret
		}
	case ^Bit_Field_Type:
		if n, ok := a.derived.(^Bit_Field_Type); ok {
			if len(n.fields) != len(m.fields) do return false
			ret := node_equal(n.backing_type, m.backing_type)
			for i in 0 ..< len(n.fields) {
				ret &= node_equal(n.fields[i], m.fields[i])
			}
			return ret
		}
	case ^Bit_Field_Field:
		if n, ok := a.derived.(^Bit_Field_Field); ok {
			ret := node_equal(n.name, m.name)
			ret &= node_equal(n.type, m.type)
			ret &= node_equal(n.bit_size, m.bit_size)
			return ret
		}
	case ^Typeid_Type:
		return true
	case:
	}

	return false
}
