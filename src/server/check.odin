package server

import "src:documents"

import "src:common"
import "src:diagnostics"

// check_unused_imports checks for unused imports and adds diagnostics
check_unused_imports :: proc(doc_ctx: documents.Document, config: ^common.Config) {
	if !config.enable_unused_imports_reporting {
		return
	}

	path := doc_ctx.filepath

	when ODIN_OS == .Windows {
		path = common.get_case_sensitive_path(path, context.temp_allocator)
	}

	encoded_path := common.path_to_uri(path, context.temp_allocator)

	// Clear existing .Unused diagnostics for this path before adding new ones
	diagnostics.begin_diagnostic_update(encoded_path, .Unused)

	unused_imports := find_unused_imports(doc_ctx, context.temp_allocator)

	for imp in unused_imports {
		diagnostics.add_unused_import_diagnostic(encoded_path, imp, doc_ctx.ast.src)
	}
}

check :: proc(paths: []string, encoded_path: string, config: ^common.Config) {
	diagnostics.check(paths, encoded_path, config)
}

check_invert_if_suggestions :: proc(doc_ctx: documents.Document, config: ^common.Config) {
	diagnostics.check_invert_if_suggestions(doc_ctx, config)
}
