package diagnostics

import "src:common"
import "src:documents"

// add_unused_import_diagnostic adds a diagnostic for an unused import
add_unused_import_diagnostic :: proc(collection: ^DiagnosticCollection, uri: string, imp: documents.Package, src: string) {
	add_diagnostic(
		collection,
		.Unused,
		uri,
		Diagnostic {
			range = common.get_token_range(imp.import_decl, src),
			severity = DiagnosticSeverity.Hint,
			code = "Unused",
			message = "unused import",
			tags = {.Unnecessary},
		},
	)
}
