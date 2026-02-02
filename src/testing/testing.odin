package ols_testing

import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:odin/ast"
import "core:odin/parser"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "src:analysis"
import "src:common"
import "src:documents"
import "src:server"
import "src:workspace"

Package :: struct {
	pkg:      string,
	filename: string,
	source:   string,
}

Source :: struct {
	main:         string,
	packages:     []Package,
	document:     ^documents.DocumentData,
	doc_ctx:      documents.Document,
	collections:  map[string]string,
	config:       common.Config,
	position:     common.Position,
	end_position: common.Position, // For range selection tests
	has_range:    bool, // True if {<} and {>} markers were found
}

// Helper to create a RequestContext from a Source for testing
make_test_request_context :: proc(src: ^Source) -> server.RequestContext {
	return server.RequestContext{doc_ctx = src.doc_ctx, config = &src.config, position = src.position}
}

@(private)
setup :: proc(src: ^Source) {
	// Use temp allocator for all allocations in this test to avoid leak reports
	// The parser internally uses context.allocator so we need to redirect it
	context.allocator = context.temp_allocator

	// Initialize the config storage - this is needed for initialize_default_collections
	// which uses common.config_storage.allocator for its allocations
	common.config_storage.allocator = context.temp_allocator

	// Initialize the documents module for cross-file operations
	documents.init()

	src.main = strings.clone(src.main, context.temp_allocator)
	src.document = new(documents.DocumentData, context.temp_allocator)
	src.document.filepath = "test/test.odin"
	src.document.text = transmute([]u8)src.main

	// Initialize the config.collections map before calling initialize_default_collections
	src.config.collections = make(map[string]string, context.temp_allocator)
	server.initialize_default_collections(&src.config, "")

	// Parse position markers: {*} for cursor, {<} for range start, {>} for range end
	parse_position_markers(src)

	workspace.register_mock_file(src.document.filepath, src.main)

	// Reset and initialize the symbol cache for this test
	// This ensures each test starts with a fresh cache
	analysis.init_symbol_cache(&src.config)

	// Initialize the diagnostic store for this test
	server.init_diagnostic_store(context.temp_allocator)

	// Create documents.Document for the test document
	src.doc_ctx, _ = server.create_document_context(src.document, &src.config)


	// Run diagnostics checks if enabled in config
	server.run_hint_diagnostics(src.doc_ctx, &src.config)

	// Collect symbols from the main document into the cache
	if ret := analysis.collect_symbols_to_cache(src.doc_ctx.ast); ret != .None {
		return
	}

	for src_pkg in src.packages {
		filename := src_pkg.filename if src_pkg.filename != "" else "package"
		fullpath := fmt.aprintf("test/%v/%v.odin", src_pkg.pkg, filename)
		workspace.register_mock_file(fullpath, src_pkg.source)
		documents.open(fullpath, src_pkg.source)
		analysis.analyze_file(fullpath, src_pkg.source)
	}
}

@(private)
teardown :: proc(src: ^Source) {
	analysis.shutdown_symbol_cache()
	server.shutdown_diagnostic_store()
	documents.shutdown()
	workspace.clear_mock_files()
	free_all(context.temp_allocator)
}

// Parse position markers from source text
// Supports: {*} for cursor position, {<} for range start, {>} for range end
@(private)
parse_position_markers :: proc(src: ^Source) {
	CURSOR_MARKER :: "{*}"
	RANGE_START_MARKER :: "{<}"
	RANGE_END_MARKER :: "{>}"
	MARKER_LENGTH :: 3

	current, last: u8
	current_line, current_character: int
	found_cursor := false
	found_range_start := false
	found_range_end := false

	// First pass: find markers and record positions
	write_index := 0
	for read_index := 0; read_index < len(src.main); {
		current = src.main[read_index]

		if last == '\r' {
			current_line += 1
			current_character = 0
		} else if current == '\n' {
			current_line += 1
			current_character = 0
		}

		// Check for markers
		remaining := len(src.main) - read_index
		if remaining >= MARKER_LENGTH {
			marker := src.main[read_index:read_index + MARKER_LENGTH]

			if marker == CURSOR_MARKER && !found_cursor {
				src.position.character = current_character
				src.position.line = current_line
				found_cursor = true
				read_index += MARKER_LENGTH
				last = current
				continue
			} else if marker == RANGE_START_MARKER && !found_range_start {
				src.position.character = current_character
				src.position.line = current_line
				found_range_start = true
				src.has_range = true
				read_index += MARKER_LENGTH
				last = current
				continue
			} else if marker == RANGE_END_MARKER && !found_range_end {
				src.end_position.character = current_character
				src.end_position.line = current_line
				found_range_end = true
				read_index += MARKER_LENGTH
				last = current
				continue
			}
		}

		// Copy character
		(transmute([]u8)src.main)[write_index] = current
		write_index += 1

		if current != '\n' && current != '\r' {
			current_character += 1
		}

		last = current
		read_index += 1
	}

	// Update the document text length
	src.document.text = transmute([]u8)src.main[:write_index]
}
