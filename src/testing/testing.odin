package ols_testing

import "core:fmt"
import "core:log"
import "core:math/rand"
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
	fullpath:          string,
	source:            string,
	source_expected:   string,
	source_actual:     string,
	position:          common.Position,
	end_position:      common.Position, // For range selection tests
	has_range:         bool, // True if {<} and {>} markers were found
	encoded_locations: []common.Location,
	skip_load:         bool, // If true, file is in workspace but not opened/loaded
}

Source :: struct {
	files:       []FileInPackage,
	collections: map[string]string,
	config:      common.Config,
	test_name:   string,
}

// Helper to create a RequestContext from a Source for testing
make_test_request_context :: proc(src: ^Source) -> server.RequestContext {
	primary := get_primary_file(src)
	doc_ctx := get_file_doc_ctx(src, primary)
	return server.RequestContext{doc = doc_ctx, config = &src.config, position = primary.position}
}

// Get document context for a file, loading it on-demand if needed
get_file_doc_ctx :: proc(src: ^Source, file: ^FileInPackage) -> documents.Document {
	doc_ctx, _ := documents.get_context(file.fullpath, &src.config)
	return doc_ctx
}

// Get the primary file (the one with cursor/range markers)
get_primary_file :: proc(src: ^Source) -> ^FileInPackage {
	for &file in src.files {
		if file.has_range || file.position.line != 0 || file.position.character != 0 {
			return &file
		}
	}
	// Default to first file if no markers found
	if len(src.files) > 0 {
		return &src.files[0]
	}
	panic("Source has no files")
}

@(private)
setup :: proc(src: ^Source) {
	// log.info("Setting up config")
	common.config_storage.allocator = context.allocator
	src.config.collections = make(map[string]string)
	server.initialize_default_collections(&src.config)

	// Initialize the documents module for cross-file operations
	// log.info("Initializing documents module")
	documents.init()
	analysis.init_symbol_cache(&src.config)
	server.init_diagnostic_store()

	files := make([dynamic]^FileInPackage, context.temp_allocator)
	for &file in src.files {
		append(&files, &file)
	}

	if src.test_name == "" {
		// generate random name to avoid conflicts
		sb := strings.builder_make(context.temp_allocator)
		strings.write_string(&sb, "test_")
		for i := 0; i < 8; i += 1 {
			strings.write_byte(&sb, byte('a' + rand.uint32() % 26))
		}
		src.test_name = strings.to_string(sb)
	}

	for &file in files {
		if file.filename == "" {
			sb := strings.builder_make(context.temp_allocator)
			// strings.write_string(&sb, src.test_name)
			// strings.write_string(&sb, "_file")
			strings.write_string(&sb, "test")
			file.filename = strings.to_string(sb)
		}

		if file.pkg == "" {
			file.pkg = "test"
		}

		sb := strings.builder_make(context.temp_allocator)
		// strings.write_string(&sb, src.test_name)
		strings.write_string(&sb, "test/")
		if file.pkg != "test" {
			strings.write_string(&sb, file.pkg)
			strings.write_string(&sb, "/")
		}
		strings.write_string(&sb, file.filename)
		strings.write_string(&sb, ".odin")
		file.fullpath = strings.to_string(sb)

		// log.debugf("Storing file %s at %s", file.filename, file.fullpath)

		parse_position_markers(file, file.fullpath)
		workspace.register_mock_file(file.fullpath, file.source)
		if file.skip_load {
			continue
		}
		documents.open(file.fullpath, file.source)
		doc_ctx, _ := documents.get_context(file.fullpath, &src.config)
		analysis.analyze_file(file.fullpath, file.source)
		server.run_hint_diagnostics(doc_ctx, &src.config)
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
parse_position_markers :: proc(file: ^FileInPackage, filepath: string) {
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
	for i := 0; i < len(file.source); {
		current := file.source[i]

		// Update line tracking before processing character
		if i > 0 && file.source[i - 1] == '\r' {
			line += 1
			character = 0
		} else if current == '\n' {
			line += 1
			character = 0
		}

		// Check for markers
		if remaining := len(file.source) - i; remaining >= MARKER_LENGTH {
			marker_str := file.source[i:i + MARKER_LENGTH]
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
	file.source = strings.to_string(builder)

	// Process collected markers
	location_positions := make([dynamic]common.Position, context.temp_allocator)

	for marker in markers {
		switch marker.type {
		case .Cursor:
			file.position = marker.position
		case .RangeStart:
			file.position = marker.position
			file.has_range = true
		case .RangeEnd:
			file.end_position = marker.position
		case .Location:
			append(&location_positions, marker.position)
		}
	}

	// Build locations from {:} marker pairs
	if len(location_positions) > 0 {
		locations := make([dynamic]common.Location, context.temp_allocator)
		for i := 0; i + 1 < len(location_positions); i += 2 {
			loc := common.Location {
				uri = common.path_to_uri(filepath),
				range = {start = location_positions[i], end = location_positions[i + 1]},
			}
			append(&locations, loc)
		}
		file.encoded_locations = locations[:]
	}
}
