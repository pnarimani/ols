package diagnostics

import "base:runtime"
import "core:strings"

// ============================================================================
// Persistent Diagnostic Store (private module-level state)
// ============================================================================

// Private persistent storage - @(private = "file") makes these file-private in Odin
@(private = "file")
g_persistent_diagnostics: map[string][DiagnosticType][dynamic]Diagnostic

@(private = "file")
g_dirty_uris: map[string]bool // URIs that need to be republished

@(private = "file")
g_allocator: runtime.Allocator

@(private = "file")
g_initialized: bool = false

// Initialize the persistent store with a specific allocator
init_diagnostic_store :: proc(allocator := context.allocator) {
	g_allocator = allocator
	g_persistent_diagnostics = make(map[string][DiagnosticType][dynamic]Diagnostic, 64, g_allocator)
	g_dirty_uris = make(map[string]bool, 32, g_allocator)
	g_initialized = true
}

// Shutdown and clear the persistent store (for testing)
shutdown_diagnostic_store :: proc() {
	if !g_initialized {
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
		delete(uri, g_allocator)
	}
	delete(g_persistent_diagnostics)
	delete(g_dirty_uris)

	g_initialized = false
}

// Initialize the persistent store lazily if not already initialized
@(private = "file")
ensure_initialized :: proc() {
	if !g_initialized {
		init_diagnostic_store(context.allocator)
	}
}

// Begin updating diagnostics of a specific type for a URI.
// This clears existing diagnostics of that type for the URI.
// Call this before adding new diagnostics via add_diagnostic.
begin_diagnostic_update :: proc(uri: string, type: DiagnosticType) {
	ensure_initialized()

	// Get or create the entry for this URI
	if uri not_in g_persistent_diagnostics {
		g_persistent_diagnostics[strings.clone(uri, g_allocator)] = {}
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
add_diagnostic :: proc(type: DiagnosticType, uri: string, diagnostic: Diagnostic) {
	ensure_initialized()

	// Get or create the entry for this URI
	if uri not_in g_persistent_diagnostics {
		g_persistent_diagnostics[strings.clone(uri, g_allocator)] = {}
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
get_merged_diagnostics :: proc(uri: string, allocator := context.temp_allocator) -> []Diagnostic {
	ensure_initialized()

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
get_uris_with_diagnostic_type :: proc(type: DiagnosticType, allocator := context.temp_allocator) -> []string {
	ensure_initialized()

	result := make([dynamic]string, 0, len(g_persistent_diagnostics), allocator)

	for uri, uri_diagnostics in g_persistent_diagnostics {
		if uri_diagnostics[type] != nil && len(uri_diagnostics[type]) > 0 {
			append(&result, uri)
		}
	}

	return result[:]
}

// Get all dirty URIs that need republishing, then clear the dirty set
get_and_clear_dirty_uris :: proc(allocator := context.temp_allocator) -> []string {
	ensure_initialized()

	result := make([dynamic]string, 0, len(g_dirty_uris), allocator)

	for uri in g_dirty_uris {
		append(&result, uri)
	}

	clear(&g_dirty_uris)

	return result[:]
}

// Get diagnostics of a specific type for an encoded path (for testing)
get_diagnostics_for_path :: proc(encoded_path: string, type: DiagnosticType, allocator := context.temp_allocator) -> []Diagnostic {
	ensure_initialized()

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
