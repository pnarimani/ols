package urilib

import "core:mem"
import "core:strings"
import "core:unicode/utf8"

// Uppercase hex characters for encoding (as array to allow variable indexing)
@(private = "package")
HEX_CHARS := [16]u8{'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'}

// encode_path encodes a string for use in the path component of a URI.
// Allows: unreserved + ":" + "@" + "/" (path can contain slashes)
// All other characters are percent-encoded.
encode_path :: proc(value: string, allocator := context.allocator) -> string {
	allowed: [256]bool = UNRESERVED
	allowed[':'] = true
	allowed['@'] = true
	allowed['/'] = true
	return encode_with_allowed(value, allowed, allocator)
}

// encode_path_segment encodes a single path segment (between slashes).
// Allows: unreserved + ":" + "@" (no "/" since it's a segment)
// All other characters are percent-encoded.
encode_path_segment :: proc(value: string, allocator := context.allocator) -> string {
	allowed: [256]bool = UNRESERVED
	allowed[':'] = true
	allowed['@'] = true
	return encode_with_allowed(value, allowed, allocator)
}

// encode_query encodes a string for use in the query component of a URI.
// Allows: unreserved + ":" + "@" + "/" + "?"
// All other characters are percent-encoded.
encode_query :: proc(value: string, allocator := context.allocator) -> string {
	allowed: [256]bool = UNRESERVED
	allowed[':'] = true
	allowed['@'] = true
	allowed['/'] = true
	allowed['?'] = true
	return encode_with_allowed(value, allowed, allocator)
}

// encode_query_component encodes a query parameter key or value.
// More restrictive - also encodes "&", "=", and "+" which have special meaning in query strings.
// Allows: unreserved only
// All other characters are percent-encoded.
encode_query_component :: proc(value: string, allocator := context.allocator) -> string {
	return encode_with_allowed(value, UNRESERVED, allocator)
}

// encode_fragment encodes a string for use in the fragment component of a URI.
// Allows: unreserved + ":" + "@" + "/" + "?"
// All other characters are percent-encoded.
encode_fragment :: proc(value: string, allocator := context.allocator) -> string {
	allowed: [256]bool = UNRESERVED
	allowed[':'] = true
	allowed['@'] = true
	allowed['/'] = true
	allowed['?'] = true
	return encode_with_allowed(value, allowed, allocator)
}

// encode_userinfo encodes a string for use in the userinfo component.
// Allows: unreserved + sub-delims + ":"
// All other characters are percent-encoded.
encode_userinfo :: proc(value: string, allocator := context.allocator) -> string {
	allowed: [256]bool = UNRESERVED
	// Add sub-delims
	allowed['!'] = true
	allowed['$'] = true
	allowed['&'] = true
	allowed['\''] = true
	allowed['('] = true
	allowed[')'] = true
	allowed['*'] = true
	allowed['+'] = true
	allowed[','] = true
	allowed[';'] = true
	allowed['='] = true
	allowed[':'] = true
	return encode_with_allowed(value, allowed, allocator)
}

// encode_host encodes a string for use in the host component.
// For reg-name: allows unreserved + sub-delims
// IPv6 addresses in brackets are handled specially - brackets preserved, content not encoded.
encode_host :: proc(value: string, allocator := context.allocator) -> string {
	// Check for IPv6 literal (starts with '[')
	if len(value) > 0 && value[0] == '[' {
		// Find closing bracket
		for i := 1; i < len(value); i += 1 {
			if value[i] == ']' {
				// Return IPv6 literal as-is (brackets + content)
				return strings.clone(value, allocator)
			}
		}
	}

	// Regular host (reg-name)
	allowed: [256]bool = UNRESERVED
	// Add sub-delims
	allowed['!'] = true
	allowed['$'] = true
	allowed['&'] = true
	allowed['\''] = true
	allowed['('] = true
	allowed[')'] = true
	allowed['*'] = true
	allowed['+'] = true
	allowed[','] = true
	allowed[';'] = true
	allowed['='] = true
	return encode_with_allowed(value, allowed, allocator)
}

// encode encodes all reserved and non-ASCII characters in a string.
// Only unreserved characters pass through unchanged.
// This is the most conservative encoding.
encode :: proc(value: string, allocator := context.allocator) -> string {
	return encode_with_allowed(value, UNRESERVED, allocator)
}

// encode_with_allowed is the internal helper that performs percent-encoding.
// Characters in the allowed set pass through unchanged.
// All other bytes (including multi-byte UTF-8 sequences) are percent-encoded.
@(private = "package")
encode_with_allowed :: proc(value: string, allowed: [256]bool, allocator := context.allocator) -> string {
	// First pass: count how many bytes need encoding to pre-allocate
	encoded_len := 0
	for b in transmute([]u8)value {
		if allowed[b] {
			encoded_len += 1
		} else {
			encoded_len += 3 // %XX
		}
	}

	// If nothing needs encoding, just clone
	if encoded_len == len(value) {
		return strings.clone(value, allocator)
	}

	// Allocate result buffer
	result := make([]u8, encoded_len, allocator)
	idx := 0

	for b in transmute([]u8)value {
		if allowed[b] {
			result[idx] = b
			idx += 1
		} else {
			result[idx] = '%'
			result[idx + 1] = HEX_CHARS[b >> 4]
			result[idx + 2] = HEX_CHARS[b & 0x0F]
			idx += 3
		}
	}

	return string(result)
}

// decode decodes percent-encoded sequences in a string.
// Returns the decoded string and an error if the input is malformed.
// The result is validated to be proper UTF-8.
decode :: proc(value: string, allocator := context.allocator) -> (string, Parse_Error) {
	// First pass: check for percent-encoding and count result length
	has_percent := false
	for b in transmute([]u8)value {
		if b == '%' {
			has_percent = true
			break
		}
	}

	// If no percent signs, just validate UTF-8 and clone
	if !has_percent {
		if !utf8.valid_string(value) {
			return "", .Invalid_UTF8
		}
		return strings.clone(value, allocator), .None
	}

	// Decode using temp allocator first, then clone to target allocator
	temp_result := make([dynamic]u8, 0, len(value), context.temp_allocator)

	data := transmute([]u8)value
	i := 0
	for i < len(data) {
		if data[i] == '%' {
			// Need at least 2 more characters
			if i + 2 >= len(data) {
				return "", .Invalid_Percent_Encoding
			}

			high := data[i + 1]
			low := data[i + 2]

			if !is_hexdig(high) || !is_hexdig(low) {
				return "", .Invalid_Percent_Encoding
			}

			decoded_byte := (hex_value(high) << 4) | hex_value(low)
			append(&temp_result, decoded_byte)
			i += 3
		} else {
			append(&temp_result, data[i])
			i += 1
		}
	}

	// Validate UTF-8
	result_str := string(temp_result[:])
	if !utf8.valid_string(result_str) {
		return "", .Invalid_UTF8
	}

	// Clone to target allocator
	return strings.clone(result_str, allocator), .None
}

// decode_lossy decodes percent-encoded sequences, replacing invalid UTF-8 with replacement character.
// This never fails but may produce replacement characters (U+FFFD) for invalid sequences.
decode_lossy :: proc(value: string, allocator := context.allocator) -> string {
	// First pass: check for percent-encoding
	has_percent := false
	for b in transmute([]u8)value {
		if b == '%' {
			has_percent = true
			break
		}
	}

	// If no percent signs, just clone
	if !has_percent {
		return strings.clone(value, allocator)
	}

	// Decode using temp allocator first
	temp_result := make([dynamic]u8, 0, len(value), context.temp_allocator)

	data := transmute([]u8)value
	i := 0
	for i < len(data) {
		if data[i] == '%' {
			// Need at least 2 more characters
			if i + 2 >= len(data) {
				// Invalid, copy as-is
				append(&temp_result, data[i])
				i += 1
				continue
			}

			high := data[i + 1]
			low := data[i + 2]

			if !is_hexdig(high) || !is_hexdig(low) {
				// Invalid, copy as-is
				append(&temp_result, data[i])
				i += 1
				continue
			}

			decoded_byte := (hex_value(high) << 4) | hex_value(low)
			append(&temp_result, decoded_byte)
			i += 3
		} else {
			append(&temp_result, data[i])
			i += 1
		}
	}

	// Clone to target allocator
	return strings.clone(string(temp_result[:]), allocator)
}

// normalize_percent_encoding normalizes percent-encoding in a string:
// - Decodes percent-encoded unreserved characters
// - Converts hex digits to uppercase
normalize_percent_encoding :: proc(value: string, allocator := context.allocator) -> (string, Parse_Error) {
	has_percent := false
	for b in transmute([]u8)value {
		if b == '%' {
			has_percent = true
			break
		}
	}

	if !has_percent {
		return strings.clone(value, allocator), .None
	}

	temp_result := make([dynamic]u8, 0, len(value), context.temp_allocator)

	data := transmute([]u8)value
	i := 0
	for i < len(data) {
		if data[i] == '%' {
			if i + 2 >= len(data) {
				return "", .Invalid_Percent_Encoding
			}

			high := data[i + 1]
			low := data[i + 2]

			if !is_hexdig(high) || !is_hexdig(low) {
				return "", .Invalid_Percent_Encoding
			}

			decoded_byte := (hex_value(high) << 4) | hex_value(low)

			// If it's an unreserved character, decode it
			if is_unreserved(decoded_byte) {
				append(&temp_result, decoded_byte)
			} else {
				// Keep encoded but normalize to uppercase
				append(&temp_result, '%')
				append(&temp_result, to_upper_hex(high))
				append(&temp_result, to_upper_hex(low))
			}
			i += 3
		} else {
			append(&temp_result, data[i])
			i += 1
		}
	}

	return strings.clone(string(temp_result[:]), allocator), .None
}

// encode_file_path encodes a filesystem path for use in a file:// URI.
// This differs from encode_path in that it also encodes ':' which is needed
// for Windows drive letters (e.g., "C:" -> "C%3A").
// Allows: unreserved + "@" + "/" (but NOT ":")
encode_file_path :: proc(value: string, allocator := context.allocator) -> string {
	allowed: [256]bool = UNRESERVED
	allowed['@'] = true
	allowed['/'] = true
	// Note: ':' is NOT allowed - must be encoded for Windows drive letters
	return encode_with_allowed(value, allowed, allocator)
}

// decode_file_path decodes a file:// URI path component to a filesystem path.
// This is an alias for decode - included for symmetry with encode_file_path.
decode_file_path :: proc(value: string, allocator := context.allocator) -> (string, Parse_Error) {
	return decode(value, allocator)
}

// path_to_file_uri converts a filesystem path to a complete file:// URI string.
// Handles Windows drive letters and forward/backward slashes.
// Input: "C:/path/to/file.odin" or "C:\path\to\file.odin"
// Output: "file:///C%3A/path/to/file.odin"
path_to_file_uri :: proc(path: string, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)

	// Convert backslashes to forward slashes
	normalized := path
	if strings.contains_rune(path, '\\') {
		normalized, _ = strings.replace_all(path, "\\", "/", context.temp_allocator)
	}

	// Write file:// prefix
	when ODIN_OS == .Windows {
		strings.write_string(&builder, "file:///")
	} else {
		strings.write_string(&builder, "file://")
	}

	// Encode the path (this will encode ':' for Windows drive letters)
	encoded := encode_file_path(normalized, context.temp_allocator)
	strings.write_string(&builder, encoded)

	return strings.to_string(builder)
}

// file_uri_to_path converts a file:// URI to a filesystem path.
// Input: "file:///C%3A/path/to/file.odin"
// Output: "C:/path/to/file.odin"
// Returns the decoded path and success boolean.
file_uri_to_path :: proc(uri: string, allocator := context.allocator) -> (string, bool) {
	// Check for file:// prefix
	prefix_with_slash := "file:///"
	prefix_without_slash := "file://"

	remaining: string
	when ODIN_OS == .Windows {
		// On Windows, expect file:/// (three slashes before drive letter)
		if strings.has_prefix(uri, prefix_with_slash) {
			remaining = uri[len(prefix_with_slash):]
		} else if strings.has_prefix(uri, prefix_without_slash) {
			remaining = uri[len(prefix_without_slash):]
		} else {
			return "", false
		}
	} else {
		// On Unix, expect file:// followed by absolute path
		if strings.has_prefix(uri, prefix_with_slash) {
			// file:/// -> / (root path)
			remaining = uri[len(prefix_without_slash):]
		} else if strings.has_prefix(uri, prefix_without_slash) {
			remaining = uri[len(prefix_without_slash):]
		} else {
			return "", false
		}
	}

	// Decode percent-encoding
	decoded, err := decode_file_path(remaining, allocator)
	if err != .None {
		return "", false
	}

	return decoded, true
}

// to_upper_hex converts a hex digit to uppercase
@(private)
to_upper_hex :: proc(b: u8) -> u8 {
	if b >= 'a' && b <= 'f' {
		return b - 32 // 'a' - 'A' = 32
	}
	return b
}
