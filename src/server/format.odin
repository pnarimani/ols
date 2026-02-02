package server

import "src:documents"
import "core:path/filepath"
import "src:common"
import "src:odin/format"
import "src:odin/printer"

import "core:log"

FormattingOptions :: struct {
	tabSize:                uint,
	insertSpaces:           bool, //tabs or spaces
	trimTrailingWhitespace: bool,
	insertFinalNewline:     bool,
	trimFinalNewlines:      bool,
}

DocumentFormattingParams :: struct {
	textDocument: TextDocumentIdentifier,
	options:      FormattingOptions,
}

get_complete_format :: proc(doc_ctx: documents.Document, config: ^common.Config) -> ([]TextEdit, bool) {
	if doc_ctx.ast.syntax_error_count > 0 {
		return {}, true
	}

	if len(doc_ctx.text) == 0 {
		return {}, true
	}

	style := format.find_config_file_or_default(filepath.dir(doc_ctx.filepath, context.temp_allocator))
	prnt := printer.make_printer(style, context.temp_allocator)

	// Copy the ast to take a pointer to it
	ast_copy := doc_ctx.ast
	src := printer.print(&prnt, &ast_copy)

	if prnt.errored_out {
		return {}, true
	}

	edit := TextEdit {
		newText = src,
		range   = common.get_document_range(doc_ctx.text),
	}

	edits := make([dynamic]TextEdit, context.temp_allocator)

	append(&edits, edit)

	return edits[:], true
}
