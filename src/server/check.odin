package server

import "src:documents"

import "src:common"
import "src:diagnostics"

// check_unused_imports checks for unused imports and adds diagnostics
check_unused_imports :: proc(doc_ctx: documents.Document, config: ^common.Config, collection: ^DiagnosticCollection) {
	if !config.enable_unused_imports_reporting {
		return
	}

	unused_imports := find_unused_imports(doc_ctx, context.temp_allocator)

	path := doc_ctx.uri.path

	when ODIN_OS == .Windows {
		path = common.get_case_sensitive_path(path, context.temp_allocator)
	}

	uri := common.create_uri(path, context.temp_allocator)

	for imp in unused_imports {
		diagnostics.add_unused_import_diagnostic(collection, uri.uri, imp, doc_ctx.ast.src)
	}
}

check :: proc(paths: []string, uri: common.Uri, config: ^common.Config, collection: ^DiagnosticCollection) {
	diagnostics.check(paths, uri, config, collection)
}

check_invert_if_suggestions :: proc(doc_ctx: documents.Document, config: ^common.Config, collection: ^DiagnosticCollection) {
	diagnostics.check_invert_if_suggestions(doc_ctx, config, collection)
}
