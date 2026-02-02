package server

import "src:documents"
import "core:slice"

import "src:common"
import "src:diagnostics"

// Re-export types from diagnostics package for backward compatibility
DiagnosticType :: diagnostics.DiagnosticType
DiagnosticCollection :: diagnostics.DiagnosticCollection
Diagnostic :: diagnostics.Diagnostic
DiagnosticSeverity :: diagnostics.DiagnosticSeverity
DiagnosticTag :: diagnostics.DiagnosticTag

make_diagnostic_collection :: diagnostics.make_diagnostic_collection
add_diagnostic :: diagnostics.add_diagnostic

// Run hint diagnostics for a document (exported for testing)
run_hint_diagnostics :: proc(doc_ctx: documents.Document, config: ^common.Config, collection: ^DiagnosticCollection) {
	diagnostics.run_hint_diagnostics(doc_ctx, config, collection)
}

push_diagnostics :: proc(collection: ^DiagnosticCollection, writer: ^Writer) {
	if collection == nil || writer == nil {
		return
	}

	merged_diagnostics := make(map[string][dynamic]Diagnostic, 16, context.temp_allocator)

	for diagnostic_type in collection.diagnostics {
		for k, v in diagnostic_type {
			diagnostic_array := &merged_diagnostics[k]

			if diagnostic_array == nil {
				merged_diagnostics[k] = make([dynamic]Diagnostic, context.temp_allocator)
				diagnostic_array = &merged_diagnostics[k]
			}

			append(diagnostic_array, ..v[:])
		}
	}

	for k, v in merged_diagnostics {
		// Find the unique diagnostics, since some poor profile settings make the checker check the same file multiple times
		unique := slice.unique(v[:])

		params := NotificationPublishDiagnosticsParams {
			uri         = k,
			diagnostics = unique,
		}

		notification := Notification {
			jsonrpc = "2.0",
			method  = "textDocument/publishDiagnostics",
			params  = params,
		}

		send_notification(notification, writer)
	}
}
