package server

import "src:documents"
import "core:slice"

import "src:common"
import "src:diagnostics"

// Re-export types from diagnostics package for backward compatibility
DiagnosticType :: diagnostics.DiagnosticType
Diagnostic :: diagnostics.Diagnostic
DiagnosticSeverity :: diagnostics.DiagnosticSeverity
DiagnosticTag :: diagnostics.DiagnosticTag

// Re-export procedures from diagnostics package
add_diagnostic :: diagnostics.add_diagnostic
begin_diagnostic_update :: diagnostics.begin_diagnostic_update
init_diagnostic_store :: diagnostics.init
shutdown_diagnostic_store :: diagnostics.shutdown

// Run hint diagnostics for a document (exported for testing)
run_hint_diagnostics :: proc(doc_ctx: documents.Document, config: ^common.Config) {
	diagnostics.run_hint_diagnostics(doc_ctx, config)
}

// Publish all dirty diagnostics to the client.
// This publishes merged diagnostics for all URIs that have been modified
// since the last call to publish_diagnostics.
publish_diagnostics :: proc(writer: ^Writer) {
	if writer == nil {
		return
	}

	dirty_uris := diagnostics.get_and_clear_dirty_uris(context.temp_allocator)

	for uri in dirty_uris {
		merged := diagnostics.get_merged_diagnostics(uri, context.temp_allocator)

		// Deduplicate diagnostics
		unique := slice.unique(merged)

		params := NotificationPublishDiagnosticsParams {
			uri         = uri,
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
