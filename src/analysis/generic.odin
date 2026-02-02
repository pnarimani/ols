package analysis

import "core:odin/ast"

is_procedure_generic :: proc(proc_type: ^ast.Proc_Type) -> bool {
	if proc_type.generic {
		return true
	}

	for param in proc_type.params.list {
		if param.type == nil {
			continue
		}

		if expr_contains_poly(param.type) {
			return true
		}
	}

	return false
}