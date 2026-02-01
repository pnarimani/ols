package server

import "core:odin/ast"


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

get_code_lenses :: proc(doc_ctx: DocumentContext, position: common.Position) -> ([]CodeLens, bool) {
	// Build fresh symbols for this request
	request_symbols := build_request_symbols(doc_ctx.imports)

	ast_context := make_ast_context(
		doc_ctx.ast,
		doc_ctx.imports,
		doc_ctx.package_name,
		doc_ctx.uri.uri,
		doc_ctx.fullpath,
		&request_symbols,
	)

	get_globals(doc_ctx.ast, &ast_context)

	symbols := make([dynamic]CodeLens, context.temp_allocator)

	if len(doc_ctx.ast.decls) == 0 {
		return {}, true
	}

	for name, global in ast_context.globals {


		if proc_lit, ok := global.expr.derived.(^ast.Proc_Lit); ok {


		}


	}


	return {}, false

}
