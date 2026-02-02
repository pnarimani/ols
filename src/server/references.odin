package server


import "src:analysis"
import "base:runtime"

import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"

import "src:common"

WalkDirectoriesData :: struct {
	doc_ctx:   ^DocumentContext,
	fullpaths: ^[dynamic]string,
}

walk_directories :: proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
	data := cast(^WalkDirectoriesData)user_data

	if info.is_dir {
		return nil, false
	}

	if info.fullpath == "" {
		return nil, false
	}

	if strings.contains(info.name, ".odin") {
		slash_path, _ := filepath.to_slash(info.fullpath, context.temp_allocator)
		if slash_path != data.doc_ctx.fullpath {
			append(data.fullpaths, strings.clone(info.fullpath))
		}
	}

	return nil, false
}

prepare_references :: proc(
	doc_ctx: DocumentContext,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
) -> (
	symbol: analysis.Symbol,
	resolve_flag: ResolveReferenceFlag,
	ok: bool,
) {
	ok = false
	pkg := ""

	if position_context.enum_type != nil {
		found := false
		done_enum: for field in position_context.enum_type.fields {
			if ident, ok := field.derived.(^ast.Ident); ok {
				if position_in_node(ident, position_context.position) {
					symbol = analysis.Symbol{
						pkg   = ast_context.current_package,
						range = common.get_token_range(ident, ast_context.file.src),
					}
					found = true
					resolve_flag = .Field
					break done_enum
				}
			} else if value, ok := field.derived.(^ast.Field_Value); ok {
				if position_in_node(value.field, position_context.position) {
					symbol = analysis.Symbol{
						range = common.get_token_range(value.field, ast_context.file.src),
						pkg   = ast_context.current_package,
					}
					found = true
					resolve_flag = .Field
					break done_enum
				} else if position_in_node(value.value, position_context.position) {
					if ident, ok := value.value.derived.(^ast.Ident); ok {
						symbol, ok = resolve_location_identifier(ast_context, ident^)
						if !ok {
							return
						}

						found = true
						resolve_flag = .Identifier
						break done_enum
					}
				}
			}
		}
		if !found {
			return
		}
	} else if position_context.bitset_type != nil {
		if position_in_node(position_context.bitset_type.elem, position_context.position) {
			symbol, ok = resolve_location_type_expression(ast_context, position_context.bitset_type.elem)
			if !ok {
				return
			}
			resolve_flag = .Identifier
		}
		return
	} else if position_context.union_type != nil {
		found := false
		for variant in position_context.union_type.variants {
			if position_in_node(variant, position_context.position) {
				if ident, _, ok := unwrap_pointer_ident(variant); ok {
					symbol, ok = resolve_location_identifier(ast_context, ident)
					resolve_flag = .Identifier

					if !ok {
						return
					}

					found = true

					break
				} else {
					return
				}
			}
		}
		if !found {
			return
		}

	} else if position_context.field_value != nil &&
	   !is_expr_basic_lit(position_context.field_value.field) &&
	   position_in_node(position_context.field_value.field, position_context.position) {
		if position_context.comp_lit != nil {
			symbol, ok = resolve_location_comp_lit_field(ast_context, position_context)
			if !ok {
				return
			}
		} else if position_context.call != nil {
			symbol, ok = resolve_location_proc_param_name(ast_context, position_context)
			if !ok {
				return
			}
		}

		resolve_flag = .Field
	} else if position_context.selector_expr != nil {
		if position_in_node(position_context.selector, position_context.position) &&
		   position_context.identifier != nil {
			ident := position_context.identifier.derived.(^ast.Ident)

			symbol, ok = resolve_location_identifier(ast_context, ident^)

			if !ok {
				return
			}

			resolve_flag = .Identifier
		} else {
			symbol, ok = resolve_location_selector(ast_context, position_context.selector_expr)
			symbol.flags -= {.Local}

			resolve_flag = .Field
		}
	} else if position_context.implicit {
		resolve_flag = .Field

		symbol, ok = resolve_location_implicit_selector(
			ast_context,
			position_context,
			position_context.implicit_selector_expr,
		)
		symbol.flags -= {.Local}

		if !ok {
			return
		}
	} else {
		// The order of these is important as a lot of the above can be defined within a struct so we
		// need to make sure we resolve that last
		if position_context.bit_field_type != nil {
			for field in position_context.bit_field_type.fields {
				if position_in_node(field.name, position_context.position) {
					symbol = analysis.Symbol{
						range = common.get_token_range(field.name, ast_context.file.src),
						pkg   = ast_context.current_package,
						uri   = doc_ctx.uri.uri,
					}
					return symbol, .Field, true
				}
				if position_in_node(field.type, position_context.position) {
					node := get_desired_expr(field.type, position_context.position)
					if symbol, ok = resolve_location_type_expression(ast_context, node); ok {
						return symbol, .Identifier, true
					}
				}
			}
		}

		if position_context.struct_type != nil {
			for field in position_context.struct_type.fields.list {
				for name in field.names {
					if position_in_node(name, position_context.position) {
						symbol = analysis.Symbol{
							range = common.get_token_range(name, ast_context.file.src),
							pkg   = ast_context.current_package,
							uri   = doc_ctx.uri.uri,
						}
						return symbol, .Field, true
					}
				}
				if position_in_node(field.type, position_context.position) {
					node := get_desired_expr(field.type, position_context.position)
					if symbol, ok = resolve_location_type_expression(ast_context, node); ok {
						return symbol, .Identifier, true
					}
				}
			}
		}

		if position_context.identifier != nil {
			ident := position_context.identifier.derived.(^ast.Ident)
			symbol, ok = resolve_location_identifier(ast_context, ident^)

			resolve_flag = .Identifier

			if !ok {
				return
			}
		} else {
			return
		}
	}
	if symbol.uri == "" {
		symbol.uri = doc_ctx.uri.uri
	}

	return symbol, resolve_flag, true
}

resolve_references :: proc(
	doc_ctx: DocumentContext,
	ast_context: ^AstContext,
	position_context: ^DocumentPositionContext,
	current_file_only := false,
) -> (
	[]common.Location,
	bool,
) {
	locations := make([dynamic]common.Location)
	fullpaths := make([dynamic]string)

	symbol, resolve_flag, ok := prepare_references(doc_ctx, ast_context, position_context)

	if !ok {
		return {}, true
	}
	symbols_and_nodes := resolve_entire_file(doc_ctx, resolve_flag)

	for k, v in symbols_and_nodes {
		if strings.equal_fold(v.symbol.uri, symbol.uri) && v.symbol.range == symbol.range {
			node_uri := common.create_uri(v.node.pos.file)

			range := common.get_token_range(v.node^, ast_context.file.src)

			//We don't have to have the `.` with, otherwise it renames the dot.
			if _, ok := v.node.derived.(^ast.Implicit_Selector_Expr); ok {
				range.start.character += 1
			}

			location := common.Location {
				range = range,
				uri   = strings.clone(node_uri.uri),
			}

			append(&locations, location)
		}
	}

	if .Local in symbol.flags || current_file_only {
		return locations[:], true
	}

	when !ODIN_TEST {
		// Copy doc_ctx so we can take a pointer to it for walk_directories
		doc_ctx_copy := doc_ctx
		walk_data := WalkDirectoriesData {
			doc_ctx   = &doc_ctx_copy,
			fullpaths = &fullpaths,
		}
		for workspace in common.config.workspace_folders {
			uri, _ := common.parse_uri(workspace.uri, context.temp_allocator)
			filepath.walk(uri.path, walk_directories, &walk_data)
		}
	}

	reset_ast_context(ast_context)

	unique_fullpaths := slice.unique(fullpaths[:])

	for fullpath in unique_fullpaths {
		dir := filepath.dir(fullpath)
		base := filepath.base(dir)
		forward_dir, _ := filepath.to_slash(dir)

		data, ok := os.read_entire_file(fullpath)

		if !ok {
			log.errorf("failed to read entire file for indexing %v", fullpath)
			continue
		}

		p := parser.Parser {
			err   = log_error_handler,
			warn  = log_warning_handler,
			flags = {.Optional_Semicolons},
		}


		pkg := new(ast.Package)
		pkg.kind = .Normal
		pkg.fullpath = fullpath
		pkg.name = base

		if base == "runtime" {
			pkg.kind = .Runtime
		}

		file := ast.File {
			fullpath = fullpath,
			src      = string(data),
			pkg      = pkg,
		}

		ok = parser.parse_file(&p, &file)

		if !ok {
			if !strings.contains(fullpath, "builtin.odin") && !strings.contains(fullpath, "intrinsics.odin") {
				log.errorf("error in parse file for indexing %v", fullpath)
			}
			continue
		}

		uri := common.create_uri(fullpath)

		// Create a DocumentContext directly for this file
		inner_doc_ctx := DocumentContext {
			uri          = uri,
			text         = data,
			ast          = file,
			fullpath     = fullpath,
			package_name = forward_dir,
		}

		// Parse imports for this file
		inner_doc_ctx.imports = parse_imports_from_ast(file, forward_dir, data, &common.config)

		in_pkg := false

		for pkg in inner_doc_ctx.imports {
			if pkg.name == symbol.pkg {
				in_pkg = true
				continue
			}
		}

		if in_pkg || symbol.pkg == inner_doc_ctx.package_name {
			symbols_and_nodes := resolve_entire_file(inner_doc_ctx, resolve_flag)
			for k, v in symbols_and_nodes {
				if strings.equal_fold(v.symbol.uri, symbol.uri) && v.symbol.range == symbol.range {
					node_uri := common.create_uri(v.node.pos.file)
					range := common.get_token_range(v.node^, string(inner_doc_ctx.text))
					//We don't have to have the `.` with, otherwise it renames the dot.
					if _, ok := v.node.derived.(^ast.Implicit_Selector_Expr); ok {
						range.start.character += 1
					}
					location := common.Location {
						range = range,
						uri   = strings.clone(node_uri.uri),
					}
					append(&locations, location)
				}
			}
		}
	}

	return locations[:], true
}

get_references :: proc(
	doc_ctx: DocumentContext,
	position: common.Position,
	current_file_only := false,
) -> (
	[]common.Location,
	bool,
) {
	// Build fresh symbols for this request
	request_symbols := build_request_symbols(doc_ctx.imports, doc_ctx.package_name, &common.config)

	ast_context := make_ast_context(
		doc_ctx.ast,
		doc_ctx.imports,
		doc_ctx.package_name,
		doc_ctx.uri.uri,
		doc_ctx.fullpath,
		&request_symbols,
	)

	position_context, ok := get_document_position_context(doc_ctx, position, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}

	ast_context.position_hint = position_context.hint

	get_globals(doc_ctx.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(doc_ctx.ast, position_context.function, &ast_context, &position_context)
	}

	locations, ok2 := resolve_references(doc_ctx, &ast_context, &position_context, current_file_only)

	temp_locations := make([dynamic]common.Location, 0, context.temp_allocator)

	for location in locations {
		temp_location := common.Location {
			range = location.range,
			uri   = strings.clone(location.uri, context.temp_allocator),
		}
		append(&temp_locations, temp_location)
	}

	return temp_locations[:], ok2
}
