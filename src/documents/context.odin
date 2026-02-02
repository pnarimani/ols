package documents

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strings"

import "src:common"

// Get a documents.Document for a given URI string. Parses AST and imports fresh.
// All allocations use the provided allocator (typically context.temp_allocator).
// Returns nil if document not found or parsing fails.
get_context :: proc(uri_string: string, config: ^common.Config, allocator := context.temp_allocator) -> (ctx: Document, ok: bool) {
	document := get(uri_string)
	if document == nil {
		return {}, false
	}

	return create_context(document, config, allocator)
}

// Create a documents.Document from a Document. Parses AST and imports fresh.
// All allocations use the provided allocator (typically context.temp_allocator).
// Caller is responsible for freeing allocator when done.
create_context :: proc(document: ^DocumentData, config: ^common.Config, allocator := context.temp_allocator) -> (ctx: Document, ok: bool) {
	if document == nil {
		return {}, false
	}

	ctx.path = document.path
	ctx.text = document.text
	ctx.fullpath = get_fullpath_from_path(document.path, allocator)
	ctx.package_name = get_package_name_from_path(document.path, allocator)
	ctx.ast, ctx.errors, ok = parse_document_text(ctx.fullpath, document.text, allocator)
	if !ok {
		return {}, false
	}
	ctx.imports = parse_imports_from_ast(ctx.ast, ctx.package_name, document.text, config, allocator)

	return ctx, true
}

// Scope parser errors to file-private and thread-local. Reset at start of parse_document_text().
@(private = "file", thread_local)
current_errors: [dynamic]ParserError

@(private = "file")
parser_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	error := ParserError {
		line    = pos.line,
		column  = pos.column,
		file    = pos.file,
		offset  = pos.offset,
		message = fmt.tprintf(msg, ..args),
	}
	append(&current_errors, error)
}

// Parse document text into AST. Returns AST and errors. All allocations use provided allocator.
// Caller is responsible for freeing allocator when done.
parse_document_text :: proc(
	path: string,
	text: []u8,
	allocator := context.temp_allocator,
) -> (
	parsed_file: ast.File,
	errors: []ParserError,
	ok: bool,
) {
	context.allocator = allocator

	p := parser.Parser {
		err   = parser_error_handler,
		warn  = common.parser_warning_handler,
		flags = {.Optional_Semicolons},
	}

	current_errors = make([dynamic]ParserError, allocator)

	fullpath := get_fullpath_from_path(path, allocator)

	pkg := new(ast.Package, allocator)
	pkg.kind = .Normal
	pkg.fullpath = fullpath

	if strings.contains(fullpath, "base/runtime") {
		pkg.kind = .Runtime
	}

	parsed_file = ast.File {
		fullpath = fullpath,
		src      = string(text),
		pkg      = pkg,
	}

	parser.parse_file(&p, &parsed_file)

	return parsed_file, current_errors[:], true
}

// Get fullpath from path, handling Windows case sensitivity
get_fullpath_from_path :: proc(path: string, allocator := context.temp_allocator) -> string {
	when ODIN_OS == .Windows {
		correct := common.get_case_sensitive_path(path, allocator)
		if correct == "" {
			// Handle tests where physical file doesn't exist
			result, _ := filepath.to_slash(path, allocator)
			return result
		} else {
			result, _ := filepath.to_slash(correct, allocator)
			return result
		}
	} else {
		return path
	}
}

// Get package name from path
get_package_name_from_path :: proc(file_path: string, allocator := context.temp_allocator) -> string {
	when ODIN_OS == .Windows {
		package_name := path.dir(file_path, allocator)
		forward, _ := filepath.to_slash(common.get_case_sensitive_path(package_name, allocator), allocator)
		if forward == "" {
			return package_name
		} else {
			return forward
		}
	} else {
		return path.dir(file_path, allocator)
	}
}

// Parse imports from AST. Returns slice of Package. Uses provided allocator.
parse_imports_from_ast :: proc(
	parsed_file: ast.File,
	package_name: string,
	text: []u8,
	config: ^common.Config,
	allocator := context.temp_allocator,
) -> []Package {
	imports := make([dynamic]Package, allocator)

	for imp, index in parsed_file.imports {
		if i := strings.index(imp.fullpath, "\""); i == -1 {
			continue
		}
		// TODO: Breakdown this range like with semantic tokens
		range := get_import_range(imp, string(text))

		//collection specified
		if i := strings.index(imp.fullpath, ":"); i != -1 && i > 1 && i < len(imp.fullpath) - 1 {
			if len(imp.fullpath) < 2 {
				continue
			}

			collection := imp.fullpath[1:i]
			p := imp.fullpath[i + 1:len(imp.fullpath) - 1]

			dir, ok := config.collections[collection]

			if !ok {
				continue
			}

			import_: Package
			import_.original = imp.fullpath
			import_.name = path.join(elems = {dir, p}, allocator = allocator)
			import_.range = range
			import_.import_decl = imp

			if imp.name.text != "" {
				import_.base = imp.name.text
				import_.base_original = path.base(import_.name, false)
			} else {
				import_.base = path.base(import_.name, false)
			}

			append(&imports, import_)
		} else {
			//relative
			if len(imp.fullpath) < 2 {
				continue
			}

			import_: Package
			import_.original = imp.fullpath
			import_.name = path.join(
				elems = {package_name, imp.fullpath[1:len(imp.fullpath) - 1]},
				allocator = allocator,
			)
			import_.name = path.clean(import_.name, allocator)
			import_.range = range
			import_.import_decl = imp

			if imp.name.text != "" {
				import_.base = imp.name.text
				import_.base_original = path.base(import_.name, false)
			} else {
				import_.base = path.base(import_.name, false)
			}

			append(&imports, import_)
		}
	}

	return imports[:]
}

get_import_range :: proc(imp: ^ast.Import_Decl, src: string) -> common.Range {
	if imp.name.text != "" {
		start := common.token_pos_to_position(imp.name.pos, src)
		end := start
		end.character += len(imp.name.text)
		return {start = start, end = end}
	}

	start := common.token_pos_to_position(imp.relpath.pos, src)
	end := start
	text_len := len(imp.relpath.text)
	end.character += text_len
	return {start = start, end = end}
}
