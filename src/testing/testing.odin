package ols_testing

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:strings"
import "src:analysis"
import "src:common"
import "src:documents"
import "src:server"
import "src:workspace"

FileInPackage :: struct {
	pkg:               string,
	filename:          string,
	source:            string,
	position:          common.Position,
	end_position:      common.Position, // For range selection tests
	has_range:         bool, // True if {<} and {>} markers were found
	encoded_locations: []common.Location,
}

Source :: struct {
	main:              string,
	main_filepath:     string,
	extra_files:       []FileInPackage,
	document:          ^documents.DocumentData,
	doc_ctx:           documents.Document,
	collections:       map[string]string,
	config:            common.Config,
	position:          common.Position,
	end_position:      common.Position, // For range selection tests
	has_range:         bool, // True if {<} and {>} markers were found
	encoded_locations: []common.Location, // Locations marked by {:} pairs
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
	// log.info("Setting up config")
	common.config_storage.allocator = context.temp_allocator
	src.config.collections = make(map[string]string, context.temp_allocator)
	server.initialize_default_collections(&src.config, "")

	// Initialize the documents module for cross-file operations
	// log.info("Initializing documents module")
	documents.init()
	analysis.init_symbol_cache(&src.config)
	server.init_diagnostic_store()

	src.main_filepath = "test/test.odin"

	// Initialize the config.collections map before calling initialize_default_collections
	// log.info("parsing main source")
	parse_position_markers(src)

	// log.infof("Source after marker parsing:\n%v", src.main)
	workspace.register_mock_file(src.main_filepath, src.main)
	src.document = documents.get(src.main_filepath)

	// Create documents.Document for the test document
	src.doc_ctx, _ = server.create_document_context(src.document, &src.config)

	// Run diagnostics checks if enabled in config
	server.run_hint_diagnostics(src.doc_ctx, &src.config)

	// Collect symbols from the main document into the cache
	if ret := analysis.collect_symbols_to_cache(src.doc_ctx.ast); ret != .None {
		return
	}

	for src_pkg in src.extra_files {
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
// Supports: {*} for cursor position, {<} for range start, {>} for range end, {:} pairs for Location ranges
@(private)
parse_position_markers :: proc(src: ^Source) {
	CURSOR_MARKER :: "{*}"
	RANGE_START_MARKER :: "{<}"
	RANGE_END_MARKER :: "{>}"
	LOCATION_MARKER :: "{:}"
	MARKER_LENGTH :: 3

	MarkerType :: enum {
		Cursor,
		RangeStart,
		RangeEnd,
		Location,
	}

	Marker :: struct {
		type:     MarkerType,
		position: common.Position,
	}

	markers := make([dynamic]Marker, context.temp_allocator)
	builder := strings.builder_make(context.temp_allocator)

	line, character := 0, 0

	// Single pass: collect markers and build cleaned source
	for i := 0; i < len(src.main); {
		current := src.main[i]

		// Update line tracking before processing character
		if i > 0 && src.main[i - 1] == '\r' {
			line += 1
			character = 0
		} else if current == '\n' {
			line += 1
			character = 0
		}

		// Check for markers
		if remaining := len(src.main) - i; remaining >= MARKER_LENGTH {
			marker_str := src.main[i:i + MARKER_LENGTH]
			marker_type: Maybe(MarkerType)

			switch marker_str {
			case CURSOR_MARKER:
				marker_type = .Cursor
			case RANGE_START_MARKER:
				marker_type = .RangeStart
			case RANGE_END_MARKER:
				marker_type = .RangeEnd
			case LOCATION_MARKER:
				marker_type = .Location
			}

			if type, ok := marker_type.?; ok {
				append(&markers, Marker{type = type, position = {line = line, character = character}})
				i += MARKER_LENGTH
				continue
			}
		}

		// Copy character to cleaned output
		strings.write_byte(&builder, current)
		if current != '\n' && current != '\r' {
			character += 1
		}
		i += 1
	}

	// Update source with cleaned text
	src.main = strings.to_string(builder)

	// Process collected markers
	location_positions := make([dynamic]common.Position, context.temp_allocator)

	for marker in markers {
		switch marker.type {
		case .Cursor:
			src.position = marker.position
		case .RangeStart:
			src.position = marker.position
			src.has_range = true
		case .RangeEnd:
			src.end_position = marker.position
		case .Location:
			append(&location_positions, marker.position)
		}
	}

	// Build locations from {:} marker pairs
	if len(location_positions) > 0 {
		locations := make([dynamic]common.Location, context.temp_allocator)
		for i := 0; i + 1 < len(location_positions); i += 2 {
			loc := common.Location {
				uri   = common.make_encoded_path(src.main_filepath),
				range = {start = location_positions[i], end = location_positions[i + 1]},
			}
			append(&locations, loc)
		}
		src.encoded_locations = locations[:]
	}
}
