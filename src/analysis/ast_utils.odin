#+feature dynamic-literals
#+feature using-stmt

package analysis

import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"
import "src:codeprint"
import "core:odin/ast"
import "core:odin/parser"

// Corrects docs and comments on a Struct_Type. Creates new nodes and adds them to the provided struct
// using the provided allocator, so `v` should have the same lifetime as the allocator.
construct_struct_field_docs :: proc(file: ast.File, v: ^ast.Struct_Type, allocator := context.allocator) {
	for field, i in v.fields.list {
		// There is currently a bug in the odin parser where it adds line comments for a field to the
		// docs of the following field, we address this problem here.
		// see https://github.com/odin-lang/Odin/issues/5353
		// Edit 2025-07-12 it looks like the comments are now added (for structs), however the comments are still
		// incorrectly added to the following fields docs, and there's an issue where it will only
		// append the comment if there is a ',' at the end of the line (meaning it can easily be
		// skipped on the last line) eg
		// Foo :: struct {
		//     foo: int // my int <-- skipped as no ',' after 'int'
		// }

		// remove any unwanted docs
		if i != len(v.fields.list) - 1 {
			next_field := v.fields.list[i + 1]
			if next_field.docs != nil && len(next_field.docs.list) > 0 {
				list := next_field.docs.list
				if list[0].pos.line == field.pos.line {
					// if the comment is missing from the appropriate field, we add it (for older versions of the parser)
					if field.comment == nil {
						field.comment = new_type(ast.Comment_Group, list[0].pos, parser.end_pos(list[0]), allocator)
						field.comment.list = list[:1]
					}
					if len(list) > 1 {
						next_field.docs = new_type(ast.Comment_Group, list[1].pos, parser.end_pos(list[len(list) - 2]), allocator)
						next_field.docs.list = list[1:]
					} else {
						next_field.docs = nil
					}
				}
			}
		} else if field.comment == nil {
			// We need to check the file to see if it contains a line comment as it might be skipped
			field.comment, _ = get_file_comment(file, field.pos.line, allocator = allocator)
		}
	}
}

// Corrects docs and comments on a Bit_Field_Type. Creates new nodes and adds them to the provided bit_field
// using the provided allocator, so `v` should have the same lifetime as the allocator.
construct_bit_field_field_docs :: proc(file: ast.File, v: ^ast.Bit_Field_Type, allocator := context.allocator) {
	for field, i in v.fields {
		// There is currently a bug in the odin parser where it adds line comments for a field to the
		// docs of the following field, we address this problem here.
		// see https://github.com/odin-lang/Odin/issues/5353
		// We check if the comment is at the start of the next field
		if i != len(v.fields) - 1 {
			next_field := v.fields[i + 1]
			if next_field.docs != nil && len(next_field.docs.list) > 0 {
				list := next_field.docs.list
				if list[0].pos.line == field.pos.line {
					if field.comments == nil {
						field.comments = new_type(ast.Comment_Group, list[0].pos, parser.end_pos(list[0]), allocator)
						field.comments.list = list[:1]
					}
					if len(list) > 1 {
						next_field.docs = new_type(ast.Comment_Group, list[1].pos, parser.end_pos(list[len(list) - 2]), allocator)
						next_field.docs.list = list[1:]
					} else {
						next_field.docs = nil
					}
				}
			}
		} else if field.comments == nil {
			// We need to check the file to see if it contains a line comment as there is no next field
			field.comments, _ = get_file_comment(file, field.pos.line, allocator = allocator)
		}
	}
}

// Retrives the comment group from the specified line of the file
// Returns the index where the comment was found
get_file_comment :: proc(file: ast.File, line: int, start_index := 0, allocator := context.allocator) -> (^ast.Comment_Group, int) {
	// TODO: linear scan might be a bit slow for files with lots of comments?
	for i := start_index; i < len(file.comments); i += 1 {
		c := file.comments[i]
		if c.pos.line == line {
			for item, j in c.list {
				comment := new_type(ast.Comment_Group, item.pos, parser.end_pos(item), allocator)
				if j == len(c.list) - 1 {
					comment.list = c.list[j:]
				} else {
					comment.list = c.list[j:j + 1]
				}
				return comment, i
			}
		}
	}
	return nil, -1
}

// Retrieves the comment group that ends on the specified line of the file
// If start_line is specified, it will only add the docs that on that line and beyond
get_file_doc :: proc(file: ast.File, end_line: int, start_line := -1, start_index := 0, allocator := context.allocator) -> (^ast.Comment_Group, int) {
	for i := start_index; i < len(file.comments); i += 1 {
		c := file.comments[i]
		if c.end.line == end_line {
			docs := new_type(ast.Comment_Group, c.pos, c.end, allocator)
			if start_line != -1 {
				for item, j in c.list {
					if item.pos.line >= start_line {
						docs.list = c.list[j:]
						return docs, i
					}
				}
			}
			docs.list = c.list
			return docs, i
		}
	}
	return nil, -1
}

// Returns the docs and comments for a list of field types
//
// We use this as the odin parser does not include comments and docs on enum and union fields
get_field_docs_and_comments :: proc(
	file: ast.File,
	fields: []^ast.Expr,
	allocator := context.allocator,
) -> (
	[dynamic]^ast.Comment_Group,
	[dynamic]^ast.Comment_Group,
) {
	docs := make([dynamic]^ast.Comment_Group, allocator)
	comments := make([dynamic]^ast.Comment_Group, allocator)
	prev_line := -1
	last_comment := -1
	last_doc := -1
	for n, i in fields {
		doc: ^ast.Comment_Group
		comment: ^ast.Comment_Group

		if n.pos.line == prev_line {
			// if we're on the same line, just add the previous docs and comments
			doc = docs[i - 1]
			comment = comments[i - 1]
		} else {
			// Check to see if there's space below the previous field for a comment
			if n.pos.line - 1 > prev_line {
				doc, last_doc = get_file_doc(
					file,
					n.pos.line - 1,
					start_line = prev_line + 1,
					start_index = last_doc + 1,
					allocator = allocator,
				)
			}

			comment, last_comment = get_file_comment(file, n.pos.line, start_index = last_comment + 1, allocator = allocator)
		}

		append(&docs, doc)
		append(&comments, comment)
		prev_line = n.pos.line
	}


	return docs, comments
}

keyword_map: map[string]struct{} = {
	"typeid"        = {},
	"string"        = {},
	"string16"      = {},
	"cstring"       = {},
	"cstring16"     = {},
	"int"           = {},
	"uint"          = {},
	"u8"            = {},
	"i8"            = {},
	"u16"           = {},
	"i16"           = {},
	"u32"           = {},
	"i32"           = {},
	"u64"           = {},
	"i64"           = {},
	"u128"          = {},
	"i128"          = {},
	"f16"           = {},
	"f32"           = {},
	"f64"           = {},
	"bool"          = {},
	"rawptr"        = {},
	"any"           = {},
	"b8"            = {},
	"b16"           = {},
	"b32"           = {},
	"b64"           = {},
	"true"          = {},
	"false"         = {},
	"nil"           = {},
	"byte"          = {},
	"rune"          = {},
	"f16be"         = {},
	"f16le"         = {},
	"f32be"         = {},
	"f32le"         = {},
	"f64be"         = {},
	"f64le"         = {},
	"i16be"         = {},
	"i16le"         = {},
	"i32be"         = {},
	"i32le"         = {},
	"i64be"         = {},
	"i64le"         = {},
	"u16be"         = {},
	"u16le"         = {},
	"u32be"         = {},
	"u32le"         = {},
	"u64be"         = {},
	"u64le"         = {},
	"i128be"        = {},
	"i128le"        = {},
	"u128be"        = {},
	"u128le"        = {},
	"complex32"     = {},
	"complex64"     = {},
	"complex128"    = {},
	"quaternion64"  = {},
	"quaternion128" = {},
	"quaternion256" = {},
	"uintptr"       = {},
}

are_keyword_aliases :: proc(a, b: string) -> bool {
	// right now only the only alias is `byte` for `u8`, so this simple check will do
	if a == "u8" && b == "byte" {
		return true
	}
	if a == "byte" && b == "u8" {
		return true
	}
	return false
}

get_attribute_objc_type :: proc(attributes: []^ast.Attribute) -> ^ast.Expr {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_type" {
					return assign.value
				}
			}
		}
	}

	return nil
}

get_attribute_objc_name :: proc(attributes: []^ast.Attribute) -> (string, bool) {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_name" {
					if lit, ok := assign.value.derived.(^ast.Basic_Lit); ok && len(lit.tok.text) > 2 {
						return lit.tok.text[1:len(lit.tok.text) - 1], true
					}
				}

			}
		}
	}

	return "", false
}

get_attribute_objc_class_name :: proc(attributes: []^ast.Attribute) -> (string, bool) {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_class" {
					if lit, ok := assign.value.derived.(^ast.Basic_Lit); ok && len(lit.tok.text) > 2 {
						return lit.tok.text[1:len(lit.tok.text) - 1], true
					}
				}

			}
		}
	}

	return "", false
}


get_attribute_objc_is_class_method :: proc(attributes: []^ast.Attribute) -> bool {
	for attribute in attributes {
		for elem in attribute.elems {
			if assign, ok := elem.derived.(^ast.Field_Value); ok {
				if ident, ok := assign.field.derived.(^ast.Ident); ok && ident.name == "objc_is_class_method" {
					if field_value, ok := assign.value.derived.(^ast.Ident); ok && field_value.name == "true" {
						return true
					}
				}

			}
		}
	}
	return false
}

unwrap_comp_literal :: proc(expr: ^ast.Expr) -> (^ast.Comp_Lit, int, bool) {
	n := 0
	expr := expr
	for expr != nil {
		if unary, ok := expr.derived.(^ast.Unary_Expr); ok {
			if unary.op.kind == .And {
				expr = unary.expr
				n += 1
			} else {
				break
			}
		} else {
			break
		}
	}

	if expr != nil {
		if comp_literal, ok := expr.derived.(^ast.Comp_Lit); ok {
			return comp_literal, n, ok
		}

		return {}, n, false
	}

	return {}, n, false
}

unwrap_pointer_ident :: proc(expr: ^ast.Expr) -> (ast.Ident, int, bool) {
	n := 0
	expr := expr
	for expr != nil {
		if pointer, ok := expr.derived.(^ast.Pointer_Type); ok {
			expr = pointer.elem
			n += 1
		} else {
			break
		}
	}

	// Check for parapoly specialization
	if expr != nil {
		if poly, ok := expr.derived.(^ast.Poly_Type); ok {
			expr = poly.specialization
		}
	}

	// Check for parapoly self
	if expr != nil {
		if call, ok := expr.derived.(^ast.Call_Expr); ok {
			expr = call.expr
		}
	}

	if expr != nil {
		if ident, ok := expr.derived.(^ast.Ident); ok {
			return ident^, n, ok
		}

		return {}, n, false
	}

	return {}, n, false
}

unwrap_pointer_expr :: proc(expr: ^ast.Expr) -> (^ast.Expr, int, bool) {
	n := 0
	expr := expr
	for expr != nil {
		if pointer, ok := expr.derived.(^ast.Pointer_Type); ok {
			expr = pointer.elem
			n += 1
		} else {
			break
		}
	}

	if expr == nil {
		return {}, n, false
	}

	return expr, n, true
}

pointer_is_soa :: proc(pointer: ast.Pointer_Type) -> bool {
	if pointer.tag != nil {
		if basic, ok := pointer.tag.derived.(^ast.Basic_Directive); ok && basic.name == "soa" {
			return true
		}
	}
	return false
}

array_is_soa :: proc(array: ast.Array_Type) -> bool {
	if array.tag != nil {
		if basic, ok := array.tag.derived.(^ast.Basic_Directive); ok && basic.name == "soa" {
			return true
		}
	}
	return false
}

array_is_simd :: proc(array: ast.Array_Type) -> bool {
	if array.tag != nil {
		if basic, ok := array.tag.derived.(^ast.Basic_Directive); ok && basic.name == "simd" {
			return true
		}
	}
	return false
}

dynamic_array_is_soa :: proc(array: ast.Dynamic_Array_Type) -> bool {
	if array.tag != nil {
		if basic, ok := array.tag.derived.(^ast.Basic_Directive); ok && basic.name == "soa" {
			return true
		}
	}
	return false
}

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

expr_contains_poly :: proc(expr: ^ast.Expr) -> bool {
	if expr == nil {
		return false
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil {
			return nil
		}
		if _, ok := node.derived.(^ast.Poly_Type); ok {
			b := cast(^bool)visitor.data
			b^ = true
			return nil
		}
		return visitor
	}

	found := false

	visitor := ast.Visitor {
		visit = visit,
		data  = &found,
	}

	ast.walk(&visitor, expr)

	return found
}

is_expr_basic_lit :: proc(expr: ^ast.Expr) -> bool {
	_, ok := expr.derived.(^ast.Basic_Lit)
	return ok
}

unwrap_attr_elem :: proc(elem: ^ast.Expr) -> (^ast.Ident, ^ast.Expr, bool) {
	#partial switch v in elem.derived {
	case ^ast.Field_Value:
		if ident, ok := v.field.derived.(^ast.Ident); ok {
			return ident, v.value, true
		}
	case ^ast.Ident:
		return v, nil, true
	}

	return nil, nil, false
}

merge_attributes :: proc(attrs: []^ast.Attribute, foreign_attrs: []^ast.Attribute, allocator := context.allocator) -> []^ast.Attribute {
	if len(foreign_attrs) == 0 {
		return attrs
	}

	new_attrs := make([dynamic]^ast.Attribute, allocator)
	attr_names := make(map[string]struct{}, context.temp_allocator)
	for attr in attrs {
		append(&new_attrs, attr)
		for elem in attr.elems {
			if ident, _, ok := unwrap_attr_elem(elem); ok {
				attr_names[ident.name] = {}
			}
		}
	}

	for attr in foreign_attrs {
		for elem in attr.elems {
			if ident, _, ok := unwrap_attr_elem(elem); ok {
				name_to_check := ident.name
				if ident.name == "link_prefix" || ident.name == "link_suffix" {
					name_to_check = "link_name"
				}
				if _, ok := attr_names[name_to_check]; !ok {
					new_attr := new_type(ast.Attribute, attr.pos, attr.end, allocator)
					elems := make([dynamic]^ast.Expr, allocator)
					append(&elems, elem)
					new_attr.elems = elems[:]
					append(&new_attrs, new_attr)
				}
			}
		}
	}
	return new_attrs[:]
}

is_variable_declaration :: proc(expr: ^ast.Expr) -> bool {
	#partial switch v in expr.derived {
	case ^ast.Comp_Lit, ^ast.Basic_Lit, ^ast.Type_Cast, ^ast.Call_Expr, ^ast.Binary_Expr:
		return true
	case:
		return false
	}
}

COMMENT_DELIMITER_LENGTH :: len("//")
#assert(COMMENT_DELIMITER_LENGTH == len("/*"))
#assert(COMMENT_DELIMITER_LENGTH == len("*/"))

// Returns the minimum indentation across all non-empty lines
@(private)
get_min_indent :: proc(lines: []string) -> int {
	min_indent := max(int)
	for line in lines {
		if strings.trim_space(line) == "" do continue
		for c, i in line {
			if !strings.is_space(c) {
				min_indent = min(min_indent, i)
				break
			}
		}
	}
	return 0 if min_indent == max(int) else min_indent
}

// Strips min_indent characters from each line and joins with newlines
@(private)
strip_indent_and_join :: proc(lines: []string, min_indent: int, allocator: mem.Allocator) -> string {
	result := make([dynamic]string, context.temp_allocator)
	for line in lines {
		if len(line) >= min_indent {
			append(&result, line[min_indent:])
		} else {
			append(&result, strings.trim_left_space(line))
		}
	}
	return strings.join(result[:], "\n", allocator)
}

// Aggregates the content from the provided comment group,
// omitting extraneous spaces and delimiters.
get_comment :: proc(comment: ^ast.Comment_Group, allocator := context.allocator) -> string {
	if comment == nil do return ""

	lines := make([dynamic]string, context.temp_allocator)

	for token in comment.list {
		if len(token.text) < COMMENT_DELIMITER_LENGTH do continue
		delimiter := token.text[:COMMENT_DELIMITER_LENGTH]

		switch delimiter {
		case "/*":
			if len(token.text) <= COMMENT_DELIMITER_LENGTH * 2 do continue
			content := token.text[COMMENT_DELIMITER_LENGTH:len(token.text) - COMMENT_DELIMITER_LENGTH]

			// Check if this is a single-line block comment (no newlines)
			if !strings.contains(content, "\n") {
				text := strings.trim_space(content)
				if text != "" do append(&lines, text)
			} else {
				// Multi-line block comment: strip leading/trailing newlines
				content = strings.trim(content, "\r\n")
				for line in strings.split_lines(content, context.temp_allocator) {
					append(&lines, line)
				}
			}

		case "//":
			text := token.text[COMMENT_DELIMITER_LENGTH:]
			append(&lines, text)

		case:
			log.error("unsupported comment delimiter")
		}
	}

	if len(lines) == 0 do return ""

	min_indent := get_min_indent(lines[:])
	return strip_indent_and_join(lines[:], min_indent, allocator)
}
