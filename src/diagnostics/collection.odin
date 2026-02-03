package diagnostics

import "src:common"
import "base:runtime"
import "core:strings"

@(private = "file")
g_persistent_diagnostics: map[FileUri][DiagnosticType][dynamic]Diagnostic

@(private = "file")
g_dirty_uris: map[FileUri]bool // URIs that need to be republished

@(private = "file")
g_allocator: runtime.Allocator

init :: proc() {
	// already initialized
	if g_allocator.procedure != nil {
		return
	}
	g_allocator = context.allocator
	g_persistent_diagnostics = make(map[FileUri][DiagnosticType][dynamic]Diagnostic, 64, g_allocator)
	g_dirty_uris = make(map[FileUri]bool, 32, g_allocator)
}

shutdown :: proc() {
	if g_allocator.procedure == nil {
		return
	}

	// Free all diagnostic strings and arrays
	for uri, &uri_diagnostics in g_persistent_diagnostics {
		for type in DiagnosticType {
			if uri_diagnostics[type] != nil {
				for &diag in uri_diagnostics[type] {
					delete(diag.message, g_allocator)
					delete(diag.code, g_allocator)
				}
				delete(uri_diagnostics[type])
			}
		}
		delete(string(uri), g_allocator)
	}
	delete(g_persistent_diagnostics)
	delete(g_dirty_uris)
	g_allocator = {}
}

FileUri :: common.FileUri

// Begin updating diagnostics of a specific type for a URI.
// This clears existing diagnostics of that type for the URI.
// Call this before adding new diagnostics via add_diagnostic.
begin_diagnostic_update :: proc(uri: FileUri, type: DiagnosticType) {
	if uri not_in g_persistent_diagnostics {
		g_persistent_diagnostics[common.clone_uri(uri, g_allocator)] = {}
	}

	uri_diagnostics := &g_persistent_diagnostics[uri]

	// Clear existing diagnostics of this type for this URI
	if uri_diagnostics[type] != nil {
		for &diag in uri_diagnostics[type] {
			delete(diag.message, g_allocator)
			delete(diag.code, g_allocator)
		}
		clear(&uri_diagnostics[type])
	} else {
		uri_diagnostics[type] = make([dynamic]Diagnostic, g_allocator)
	}

	// Mark as dirty for publishing
	g_dirty_uris[uri] = true
}

// Add a diagnostic directly to the persistent store.
// Call begin_diagnostic_update first to clear old diagnostics of this type.
add_diagnostic :: proc(type: DiagnosticType, uri: FileUri, diagnostic: Diagnostic) {
	if uri not_in g_persistent_diagnostics {
		g_persistent_diagnostics[common.clone_uri(uri, g_allocator)] = {}
	}

	uri_diagnostics := &g_persistent_diagnostics[uri]

	if uri_diagnostics[type] == nil {
		uri_diagnostics[type] = make([dynamic]Diagnostic, g_allocator)
	}

	// Clone the diagnostic strings for ownership using the store's allocator
	cloned_diag := diagnostic
	cloned_diag.message = strings.clone(diagnostic.message, g_allocator)
	cloned_diag.code = strings.clone(diagnostic.code, g_allocator)

	append(&uri_diagnostics[type], cloned_diag)

	// Mark as dirty for publishing
	g_dirty_uris[uri] = true
}

// Get all merged diagnostics for a URI (all types combined)
get_merged_diagnostics :: proc(uri: FileUri, allocator := context.temp_allocator) -> []Diagnostic {
	if uri not_in g_persistent_diagnostics {
		return {}
	}

	uri_diagnostics := g_persistent_diagnostics[uri]

	// Count total diagnostics
	total := 0
	for type in DiagnosticType {
		if uri_diagnostics[type] != nil {
			total += len(uri_diagnostics[type])
		}
	}

	if total == 0 {
		return {}
	}

	result := make([dynamic]Diagnostic, 0, total, allocator)

	for type in DiagnosticType {
		if uri_diagnostics[type] != nil {
			append(&result, ..uri_diagnostics[type][:])
		}
	}

	return result[:]
}

// Get all URIs that currently have diagnostics of a specific type
get_uris_with_diagnostic_type :: proc(type: DiagnosticType, allocator := context.temp_allocator) -> []common.FileUri {
	result := make([dynamic]common.FileUri, 0, len(g_persistent_diagnostics), allocator)

	for uri, uri_diagnostics in g_persistent_diagnostics {
		if uri_diagnostics[type] != nil && len(uri_diagnostics[type]) > 0 {
			append(&result, uri)
		}
	}

	return result[:]
}

// Get all dirty URIs that need republishing, then clear the dirty set
get_and_clear_dirty_uris :: proc(allocator := context.temp_allocator) -> []common.FileUri {
	result := make([dynamic]common.FileUri, 0, len(g_dirty_uris), allocator)

	for uri in g_dirty_uris {
		append(&result, uri)
	}

	clear(&g_dirty_uris)

	return result[:]
}

// Get diagnostics of a specific type for an encoded path (for testing)
get_diagnostics_for_path :: proc(encoded_path: FileUri, type: DiagnosticType, allocator := context.temp_allocator) -> []Diagnostic {
	if encoded_path not_in g_persistent_diagnostics {
		return {}
	}

	path_diagnostics := g_persistent_diagnostics[encoded_path]

	if path_diagnostics[type] == nil || len(path_diagnostics[type]) == 0 {
		return {}
	}

	result := make([dynamic]Diagnostic, 0, len(path_diagnostics[type]), allocator)
	append(&result, ..path_diagnostics[type][:])

	return result[:]
}
