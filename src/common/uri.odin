package common

import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import "src:urilib"

FileUri :: distinct string

// Decode an encoded path string (e.g., "file:///C%3A/path/to/file.odin") to a filesystem path
// Returns the decoded path using forward slashes as separator
uri_to_path :: proc {
	uri_to_path_file_uri,
	uri_to_path_string,
}

uri_to_path_file_uri :: proc(uri: FileUri, allocator := context.allocator) -> (string, bool) #optional_ok {
	return uri_to_path_string(string(uri), allocator)
}

uri_to_path_string :: proc(uri: string, allocator := context.allocator) -> (string, bool) #optional_ok {
	decoded, ok := urilib.file_uri_to_path(uri, context.temp_allocator)
	if !ok {
		return {}, false
	}

	when ODIN_OS == .Windows {
		// Get the actual case from filesystem
		return get_case_sensitive_path(decoded, allocator), true
	} else {
		return decoded, true
	}

}

// Encode a filesystem path for LSP protocol responses
// Input: filesystem path (e.g., "C:/path/to/file.odin" or "C:\path\to\file.odin")
// Output: encoded path string (e.g., "file:///C%3A/path/to/file.odin")
path_to_uri :: proc(path: string, allocator := context.allocator) -> FileUri {
	path := path

	when ODIN_OS == .Windows {
		path = get_case_sensitive_path(path, context.temp_allocator)
	}

	return FileUri(urilib.path_to_file_uri(path, allocator))
}

clone_uri :: proc(uri: FileUri, allocator := context.allocator) -> FileUri {
	return FileUri(strings.clone(string(uri), allocator))
}
