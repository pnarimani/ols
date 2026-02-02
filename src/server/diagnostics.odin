package server

import "src:documents"
import "base:runtime"
import "core:log"
import "core:slice"
import "core:strings"

import "src:common"

DiagnosticType :: enum {
	Syntax,
	Unused,
	Check,
	Hint,
}

// DiagnosticCollection holds diagnostics computed for a request
DiagnosticCollection :: struct {
	diagnostics: [DiagnosticType]map[string][dynamic]Diagnostic,
}

make_diagnostic_collection :: proc() -> DiagnosticCollection {
	collection := DiagnosticCollection{}
	for &diag_map in collection.diagnostics {
		diag_map = make(map[string][dynamic]Diagnostic, 16)
	}
	return collection
}

// Run hint diagnostics for a document (exported for testing)
run_hint_diagnostics :: proc(doc_ctx: documents.Document, config: ^common.Config, collection: ^DiagnosticCollection) {
	if config != nil && config.enable_invert_if_diagnostics {
		check_invert_if_suggestions(doc_ctx, config, collection)
	}
}

add_diagnostic :: proc(collection: ^DiagnosticCollection, type: DiagnosticType, uri: string, diagnostic: Diagnostic) {
	if collection == nil {
		return
	}

	diagnostic_type := &collection.diagnostics[type]

	diagnostic_array := &diagnostic_type[uri]

	if diagnostic_array == nil {
		diagnostic_type[strings.clone(uri)] = make([dynamic]Diagnostic)
		diagnostic_array = &diagnostic_type[uri]
	}

	diagnostic := diagnostic
	diagnostic.message = strings.clone(diagnostic.message)
	diagnostic.code = strings.clone(diagnostic.code)

	append(diagnostic_array, diagnostic)
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
