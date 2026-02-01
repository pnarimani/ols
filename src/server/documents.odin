package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strings"

import "src:common"

ParserError :: struct {
	message: string,
	line:    int,
	column:  int,
	file:    string,
	offset:  int,
}

Package :: struct {
	name:          string, //the entire absolute path to the directory
	base:          string,
	base_original: string,
	original:      string,
	range:         common.Range,
	import_decl:   ^ast.Import_Decl,
}

// DocumentContext holds parsed data for a document. Computed fresh per-request using temp allocator.
// All data is owned by the allocator passed to create_document_context().
DocumentContext :: struct {
	uri:          common.Uri, // Reference to Document.uri (not owned)
	text:         []u8, // Reference to Document.text (not owned)
	ast:          ast.File, // Parsed AST (owned by allocator)
	imports:      []Package, // Parsed imports (owned by allocator)
	package_name: string, // Package directory path (owned by allocator)
	fullpath:     string, // Full file path (owned by allocator)
	errors:       []ParserError, // Parser errors (owned by allocator)
}

// RequestContext bundles together all data needed for handling a request.
// Created fresh per-request with data from DocumentContext and symbols.
RequestContext :: struct {
	doc_ctx:  DocumentContext,
	config:   ^common.Config,
	position: common.Position,
	symbols:  SymbolCollection,
}

// Creates a RequestContext for a document at a given position.
// All data is allocated using context.temp_allocator.
make_request_context :: proc(doc: ^Document, pos: common.Position, config: ^common.Config) -> (RequestContext, bool) {
	doc_ctx, ok := create_document_context(doc, config)
	if !ok {
		return {}, false
	}

	symbols := build_request_symbols(doc_ctx.imports, config)

	return RequestContext{doc_ctx = doc_ctx, config = config, position = pos, symbols = symbols}, true
}

Document :: struct {
	uri:  common.Uri,
	text: []u8,
}


DocumentStorage :: struct {
	allocator: mem.Allocator,
	documents: map[string]Document,
}

document_storage: DocumentStorage

// Initialize document storage with a persistent allocator.
// Must be called before any document operations.
document_storage_init :: proc() {
	document_storage.allocator = context.allocator
	document_storage.documents = make(map[string]Document, document_storage.allocator)
}

document_storage_shutdown :: proc() {
	for k, v in document_storage.documents {
		delete(v.text, document_storage.allocator)
		common.delete_uri(v.uri, document_storage.allocator)
		delete(k, document_storage.allocator)
	}

	delete(document_storage.documents)
}

// Load a document from disk and store it in document_storage.
// Returns pointer to the stored document, or nil on failure.
document_load_from_disk :: proc(uri: common.Uri) -> ^Document {
	fullpath := get_fullpath_from_uri(uri.path, context.temp_allocator)
	
	data, read_ok := os.read_entire_file(fullpath, context.temp_allocator)
	if !read_ok {
		log.errorf("Failed to read file from disk: %v", uri.path)
		return nil
	}

	// Create document and store it in persistent storage
	document := Document {
		uri  = common.clone_uri(uri, document_storage.allocator),
		text = transmute([]u8)strings.clone(string(data), document_storage.allocator),
	}

	key := strings.clone(uri.path, document_storage.allocator)
	document_storage.documents[key] = document

	return &document_storage.documents[key]
}

document_get :: proc(uri_string: string) -> ^Document {
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return nil
	}

	if document, ok := &document_storage.documents[uri.path]; ok {
		return document
	}

	return document_load_from_disk(uri)
}

// Create a DocumentContext from a Document. Parses AST and imports fresh.
// All allocations use the provided allocator (typically context.temp_allocator).
// Caller is responsible for freeing allocator when done.
create_document_context :: proc(document: ^Document, config: ^common.Config) -> (ctx: DocumentContext, ok: bool) {
	if document == nil {
		return {}, false
	}

	ctx.uri = document.uri
	ctx.text = document.text
	ctx.fullpath = get_fullpath_from_uri(document.uri.path)
	ctx.package_name = get_package_name_from_uri(document.uri.path)
	ctx.ast, ctx.errors, ok = parse_document_text(ctx.fullpath, document.text)
	if !ok {
		return {}, false
	}
	ctx.imports = parse_imports_from_ast(ctx.ast, ctx.package_name, document.text, config)

	return ctx, true
}

/*
	Client opens a document with transferred text
*/

document_open :: proc(uri_string: string, text: string, config: ^common.Config, writer: ^Writer) -> common.Error {
	// Parse URI with temp allocator first, then clone to persistent storage
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		log.error("Failed to parse uri")
		return .ParseError
	}

	if document, ok := &document_storage.documents[uri.path]; ok {
		// Document already exists, update it
		// Free old data with persistent allocator
		common.delete_uri(document.uri, document_storage.allocator)
		delete(document.text, document_storage.allocator)

		// Clone new data to persistent storage
		document.uri = common.clone_uri(uri, document_storage.allocator)
		document.text = transmute([]u8)strings.clone(text, document_storage.allocator)
	} else {
		// New document - clone data to persistent storage
		document := Document {
			uri  = common.clone_uri(uri, document_storage.allocator),
			text = transmute([]u8)strings.clone(text, document_storage.allocator),
		}

		key := strings.clone(uri.path, document_storage.allocator)
		document_storage.documents[key] = document
	}

	return .None
}


/*
	Function that applies changes to the given document through incremental syncronization
*/
document_apply_changes :: proc(
	uri_string: string,
	changes: [dynamic]TextDocumentContentChangeEvent,
	version: Maybe(int),
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &document_storage.documents[uri.path]

	if document == nil {
		log.errorf("Client called change on an document not opened: %v ", uri.path)
		return .InvalidRequest
	}

	for change in changes {
		//for some reason sublime doesn't seem to care even if i tell it to do incremental sync
		if range, ok := change.range.(common.Range); ok {
			absolute_range, ok := common.get_absolute_range(range, document.text)

			if !ok {
				return .ParseError
			}

			//lower bound is before the change
			lower := document.text[:absolute_range.start]

			//new change between lower and upper
			middle := change.text

			//upper bound is after the change
			upper := document.text[absolute_range.end:]

			//total new size needed
			new_size := len(lower) + len(change.text) + len(upper)

			new_text := make([]u8, new_size, document_storage.allocator)

			//join the 3 splices into the text
			copy(new_text, lower)
			copy(new_text[len(lower):], middle)
			copy(new_text[len(lower) + len(middle):], upper)

			delete(document.text, document_storage.allocator)

			document.text = new_text
		} else {
			new_text := make([]u8, len(change.text), document_storage.allocator)
			copy(new_text, change.text)
			delete(document.text, document_storage.allocator)
			document.text = new_text
		}
	}

	return .None
}

document_close :: proc(uri_string: string) -> common.Error {
	log.infof("document_close: %v", uri_string)

	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &document_storage.documents[uri.path]

	if document == nil {
		log.errorf("Client called close on a document that was never opened: %v ", uri.path)
		return .InvalidRequest
	}

	common.delete_uri(document.uri, document_storage.allocator)
	delete(document.text, document_storage.allocator)

	// The key in the map was cloned with persistent allocator, need to free it
	for k, _ in document_storage.documents {
		if k == uri.path {
			delete(k, document_storage.allocator)
			break
		}
	}
	delete_key(&document_storage.documents, uri.path)

	return .None
}

// Scope parser errors to file-private and thread-local. Reset at start of parse_document_text().
@(private = "file", thread_local)
current_errors: [dynamic]ParserError

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
	uri_path: string,
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

	fullpath := get_fullpath_from_uri(uri_path, allocator)

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

// Get fullpath from URI path, handling Windows case sensitivity
get_fullpath_from_uri :: proc(uri_path: string, allocator := context.temp_allocator) -> string {
	when ODIN_OS == .Windows {
		correct := common.get_case_sensitive_path(uri_path, allocator)
		if correct == "" {
			// Handle tests where physical file doesn't exist
			result, _ := filepath.to_slash(uri_path, allocator)
			return result
		} else {
			result, _ := filepath.to_slash(correct, allocator)
			return result
		}
	} else {
		return uri_path
	}
}

// Get package name from URI path
get_package_name_from_uri :: proc(uri_path: string, allocator := context.temp_allocator) -> string {
	when ODIN_OS == .Windows {
		package_name := path.dir(uri_path, allocator)
		forward, _ := filepath.to_slash(common.get_case_sensitive_path(package_name, allocator), allocator)
		if forward == "" {
			return package_name
		} else {
			return forward
		}
	} else {
		return path.dir(uri_path, allocator)
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
