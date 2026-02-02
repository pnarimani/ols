package server

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strings"

import "src:analysis"
import "src:common"
import doc "src:documents"

// Type aliases for backwards compatibility - these will be removed once all code migrates to doc package
ParserError :: doc.ParserError
Package :: doc.Package
Document :: doc.DocumentData
DocumentContext :: doc.Document

// RequestContext bundles together all data needed for handling a request.
// Created fresh per-request with data from DocumentContext and symbols.
RequestContext :: struct {
	doc_ctx:  DocumentContext,
	config:   ^common.Config,
	position: common.Position,
	symbols:  analysis.SymbolCollection,
}

// Creates a RequestContext for a document at a given position.
// All data is allocated using context.temp_allocator.
make_request_context :: proc(d: ^Document, pos: common.Position, config: ^common.Config) -> (RequestContext, bool) {
	doc_ctx, ok := create_document_context(d, config)
	if !ok {
		return {}, false
	}

	symbols := build_request_symbols(doc_ctx.imports, doc_ctx.package_name, config)

	return RequestContext{doc_ctx = doc_ctx, config = config, position = pos, symbols = symbols}, true
}

// Delegate to doc package
document_storage_init :: doc.init
document_storage_shutdown :: doc.shutdown

document_get :: doc.get

create_document_context :: doc.create_context

document_apply_changes :: proc(
	uri_string: string,
	changes: [dynamic]TextDocumentContentChangeEvent,
	version: Maybe(int),
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	// Convert to doc.ContentChangeEvent slice
	doc_changes := make([]doc.ContentChangeEvent, len(changes), context.temp_allocator)
	for change, i in changes {
		// Extract the range from the union (if present)
		change_range: union {
			common.Range,
		}
		if r, ok := change.range.(common.Range); ok {
			change_range = r
		}
		doc_changes[i] = doc.ContentChangeEvent {
			range = change_range,
			text  = change.text,
		}
	}
	return doc.apply_changes(uri_string, doc_changes, version)
}

document_close :: doc.close
get_fullpath_from_uri :: doc.get_fullpath_from_uri
get_package_name_from_uri :: doc.get_package_name_from_uri
parse_imports_from_ast :: doc.parse_imports_from_ast
get_import_range :: doc.get_import_range