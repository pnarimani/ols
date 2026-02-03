package server

import "src:documents"
import "core:odin/ast"

import "src:analysis"
import "src:common"


CodeLensClientCapabilities :: struct {
	dynamicRegistration: bool,
}

CodeLensOptions :: struct {
	resolveProvider: bool,
}

CodeLens :: struct {
	range:   common.Range,
	command: Command,
	data:    string,
}

get_code_lenses :: proc(doc_ctx: ^documents.Document, position: common.Position) -> ([]CodeLens, bool) {
	// Build symbol cache for this request's packages
	load_document_packages(doc_ctx)

	ast_context := make_ast_context(doc_ctx, context.allocator)

	get_globals(doc_ctx.syntaxTree, &ast_context)

	symbols := make([dynamic]CodeLens, context.temp_allocator)

	if len(doc_ctx.syntaxTree.decls) == 0 {
		return {}, true
	}

	for name, global in ast_context.globals {


		if proc_lit, ok := global.expr.derived.(^ast.Proc_Lit); ok {


		}


	}


	return {}, false

}
