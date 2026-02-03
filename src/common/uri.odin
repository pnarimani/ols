package common

import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

// Decode an encoded path string (e.g., "file:///C%3A/path/to/file.odin") to a filesystem path
// Returns the decoded path using forward slashes as separator
uri_to_path :: proc(uri: string, allocator: mem.Allocator) -> (string, bool) {
	decoded, ok := decode_percent(uri, allocator)
	if !ok {
		return "", false
	}

	starts := "file:///"
	start_index := len(starts)

	if !starts_with(decoded, starts) {
		delete(decoded, allocator)
		return "", false
	}

	when ODIN_OS != .Windows {
		start_index -= 1
	}

	// Extract just the path portion
	path := strings.clone(decoded[start_index:], allocator)
	delete(decoded, allocator)
	return path, true
}

// Encode a filesystem path for LSP protocol responses
// Input: filesystem path (e.g., "C:/path/to/file.odin" or "C:\path\to\file.odin")
// Output: encoded path string (e.g., "file:///C%3A/path/to/file.odin")
path_to_uri :: proc(path: string, allocator := context.allocator) -> string {
	path_forward, _ := filepath.to_slash(path, context.temp_allocator)

	builder := strings.builder_make(allocator)

	when ODIN_OS == .Windows && !ODIN_TEST {
		strings.write_string(&builder, "file:///")
	} else {
		strings.write_string(&builder, "file://")
	}

	strings.write_string(&builder, encode_percent(path_forward, context.temp_allocator))

	return strings.to_string(builder)
}

encode_percent :: proc(value: string, allocator: mem.Allocator) -> string {
	builder := strings.builder_make(allocator)

	data := transmute([]u8)value
	index: int

	for index < len(value) {
		r, w := utf8.decode_rune(data[index:])

		if r > 127 || r == ':' {
			for i := 0; i < w; i += 1 {
				strings.write_string(
					&builder,
					strings.concatenate({"%", fmt.tprintf("%X", data[index + i])}, context.temp_allocator),
				)
			}
		} else {
			strings.write_byte(&builder, data[index])
		}

		index += w
	}

	return strings.to_string(builder)
}

@(private)
starts_with :: proc(value: string, starts_with: string) -> bool {
	if len(value) < len(starts_with) {
		return false
	}

	for i := 0; i < len(starts_with); i += 1 {
		if value[i] != starts_with[i] {
			return false
		}
	}

	return true
}

@(private)
decode_percent :: proc(value: string, allocator: mem.Allocator) -> (string, bool) {
	builder := strings.builder_make(allocator)

	for i := 0; i < len(value); i += 1 {
		if value[i] == '%' {
			if i + 2 < len(value) {
				v, ok := strconv.parse_i64_of_base(value[i + 1:i + 3], 16)

				if !ok {
					strings.builder_destroy(&builder)
					return "", false
				}

				strings.write_byte(&builder, cast(byte)v)

				i += 2
			} else {
				strings.builder_destroy(&builder)
				return "", false
			}
		} else {
			strings.write_byte(&builder, value[i])
		}
	}

	return strings.to_string(builder), true
}
