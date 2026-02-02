package server

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strings"

import "src:analysis"
import "src:common"
import "src:documents"

// Type aliases for backwards compatibility - these will be removed once all code migrates to doc package
ParserError :: documents.ParserError
Package :: documents.Package

// RequestContext bundles together all data needed for handling a request.
// Created fresh per-request with data from documents.Document.
// Symbol access is through the analysis package's cache helpers.
RequestContext :: struct {
	doc_ctx:  documents.Document,
	config:   ^common.Config,
	position: common.Position,
}

// Creates a RequestContext for a document at a given position.
// All data is allocated using context.temp_allocator.
// Builds the symbol cache for the request's imports.
make_request_context :: proc(d: ^documents.DocumentData, pos: common.Position, config: ^common.Config) -> (RequestContext, bool) {
	doc_ctx, ok := create_document_context(d, config)
	if !ok {
		return {}, false
	}

	// Build symbol cache for this request's packages
	load_document_packages(doc_ctx)

	return RequestContext{doc_ctx = doc_ctx, config = config, position = pos}, true
}

// Delegate to doc package
document_storage_init :: documents.init
document_storage_shutdown :: documents.shutdown

document_get :: documents.get

create_document_context :: documents.create_context

document_apply_changes :: proc(
	uri_string: string,
	changes: [dynamic]TextDocumentContentChangeEvent,
	version: Maybe(int),
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	// Convert to doc.ContentChangeEvent slice
	doc_changes := make([]documents.ContentChangeEvent, len(changes), context.temp_allocator)
	for change, i in changes {
		// Extract the range from the union (if present)
		change_range: union {
			common.Range,
		}
		if r, ok := change.range.(common.Range); ok {
			change_range = r
		}
		doc_changes[i] = documents.ContentChangeEvent {
			range = change_range,
			text  = change.text,
		}
	}
	return documents.apply_changes(uri_string, doc_changes, version)
}

document_close :: documents.close
get_fullpath_from_path :: documents.get_fullpath_from_path
get_package_name_from_path :: documents.get_package_name_from_path
parse_imports_from_ast :: documents.parse_imports_from_ast