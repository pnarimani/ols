package diagnostics

import "src:common"
import "src:documents"

// Run hint diagnostics for a document
run_hint_diagnostics :: proc(doc_ctx: documents.Document, config: ^common.Config, collection: ^DiagnosticCollection) {
	if config != nil && config.enable_invert_if_diagnostics {
		check_invert_if_suggestions(doc_ctx, config, collection)
	}
}
