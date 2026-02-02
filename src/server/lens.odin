package server

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

get_code_lenses :: proc(doc_ctx: DocumentContext, position: common.Position) -> ([]CodeLens, bool) {
	// Build symbol cache for this request's packages
	analysis.build_cache_for_request(doc_ctx.imports, doc_ctx.package_name)

	ast_context := make_ast_context(
		doc_ctx.ast,
		doc_ctx.imports,
		doc_ctx.package_name,
		doc_ctx.uri.uri,
		doc_ctx.fullpath,
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
