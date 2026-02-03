package common

import "core:fmt"
import "core:mem"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"
import "src:urilib"

// Decode an encoded path string (e.g., "file:///C%3A/path/to/file.odin") to a filesystem path
// Returns the decoded path using forward slashes as separator
uri_to_path :: urilib.file_uri_to_path

// Encode a filesystem path for LSP protocol responses
// Input: filesystem path (e.g., "C:/path/to/file.odin" or "C:\path\to\file.odin")
// Output: encoded path string (e.g., "file:///C%3A/path/to/file.odin")
path_to_uri :: urilib.path_to_file_uri