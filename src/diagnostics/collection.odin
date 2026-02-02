package diagnostics

import "core:strings"

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
