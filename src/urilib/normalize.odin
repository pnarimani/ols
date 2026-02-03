package urilib

import "core:mem"
import "core:strings"
import "core:unicode"

// normalize returns a normalized copy of the URI per RFC 3986 Section 6.
// Normalization includes:
// - Case normalization (scheme and host to lowercase)
// - Percent-encoding normalization (decode unreserved, uppercase hex)
// - Path normalization (remove dot segments)
// - Scheme-based normalization (remove default ports, empty path -> "/" when authority present)
normalize :: proc(uri: URI, allocator := context.allocator) -> (URI, Parse_Error) {
	result := make_uri()

	// Normalize scheme (lowercase)
	if scheme, ok := uri.scheme.?; ok {
		result.scheme = strings.to_lower(scheme, allocator)
	}

	// Normalize userinfo (percent-encoding normalization)
	if userinfo, ok := uri.userinfo.?; ok {
		normalized, err := normalize_percent_encoding(userinfo, allocator)
		if err != .None {
			destroy(&result, allocator)
			return make_uri(), err
		}
		result.userinfo = normalized
	}

	// Normalize host (lowercase + percent-encoding normalization)
	if host, ok := uri.host.?; ok {
		// First normalize percent-encoding
		normalized, err := normalize_percent_encoding(host, context.temp_allocator)
		if err != .None {
			destroy(&result, allocator)
			return make_uri(), err
		}
		// Then lowercase (except for IPv6 which is already handled)
		result.host = strings.to_lower(normalized, allocator)
	}

	// Normalize port (remove default port for known schemes)
	result.port = uri.port
	if scheme, ok := uri.scheme.?; ok {
		if port, has_port := uri.port.?; has_port {
			scheme_lower := strings.to_lower(scheme, context.temp_allocator)
			if default_port, has_default := DEFAULT_PORTS[scheme_lower]; has_default {
				if port == default_port {
					result.port = nil // Remove default port
				}
			}
		}
	}

	// Normalize path
	// 1. Percent-encoding normalization
	normalized_path, err := normalize_percent_encoding(uri.path, context.temp_allocator)
	if err != .None {
		destroy(&result, allocator)
		return make_uri(), err
	}
	// 2. Remove dot segments
	result.path = remove_dot_segments(normalized_path, allocator)

	// If authority is present and path is empty, path should be "/"
	if has_authority(uri) && len(result.path) == 0 {
		if result.path != "" {
			delete(result.path, allocator)
		}
		result.path = strings.clone("/", allocator)
	}

	// Normalize query (percent-encoding normalization)
	if query, ok := uri.query.?; ok {
		normalized, err := normalize_percent_encoding(query, allocator)
		if err != .None {
			destroy(&result, allocator)
			return make_uri(), err
		}
		result.query = normalized
	}

	// Normalize fragment (percent-encoding normalization)
	if fragment, ok := uri.fragment.?; ok {
		normalized, err := normalize_percent_encoding(fragment, allocator)
		if err != .None {
			destroy(&result, allocator)
			return make_uri(), err
		}
		result.fragment = normalized
	}

	return result, .None
}

// remove_dot_segments implements the algorithm from RFC 3986 Section 5.2.4.
// It removes "." and ".." segments from a path.
remove_dot_segments :: proc(path: string, allocator := context.allocator) -> string {
	if len(path) == 0 {
		return strings.clone("", allocator)
	}

	// Use a dynamic array as the output buffer (working with segments)
	output := make([dynamic]string, 0, 8, context.temp_allocator)
	input := path

	for len(input) > 0 {
		// A: If the input buffer begins with a prefix of "../" or "./"
		if strings.has_prefix(input, "../") {
			input = input[3:]
			continue
		}
		if strings.has_prefix(input, "./") {
			input = input[2:]
			continue
		}

		// B: If the input buffer begins with a prefix of "/./" or "/."
		// where "." is a complete path segment
		if strings.has_prefix(input, "/./") {
			input = input[2:] // Replace with "/"
			continue
		}
		if input == "/." {
			input = "/"
			continue
		}

		// C: If the input buffer begins with a prefix of "/../" or "/.."
		// where ".." is a complete path segment
		if strings.has_prefix(input, "/../") {
			input = input[3:] // Replace with "/"
			// Remove last segment from output
			if len(output) > 0 {
				pop(&output)
			}
			continue
		}
		if input == "/.." {
			input = "/"
			// Remove last segment from output
			if len(output) > 0 {
				pop(&output)
			}
			continue
		}

		// D: If the input buffer consists only of "." or ".."
		if input == "." || input == ".." {
			input = ""
			continue
		}

		// E: Move the first path segment (including initial "/" if any)
		// to the end of the output buffer
		if input[0] == '/' {
			// Find the next "/" or end
			seg_end := 1
			for seg_end < len(input) && input[seg_end] != '/' {
				seg_end += 1
			}
			append(&output, input[:seg_end])
			input = input[seg_end:]
		} else {
			// Find the next "/" or end
			seg_end := 0
			for seg_end < len(input) && input[seg_end] != '/' {
				seg_end += 1
			}
			append(&output, input[:seg_end])
			input = input[seg_end:]
		}
	}

	// Concatenate output segments
	return strings.concatenate(output[:], allocator)
}

// normalize_case normalizes the case of scheme and host components.
// Returns a new URI with normalized case. Other components are cloned as-is.
normalize_case :: proc(uri: URI, allocator := context.allocator) -> URI {
	result := make_uri()

	// Scheme to lowercase
	if scheme, ok := uri.scheme.?; ok {
		result.scheme = strings.to_lower(scheme, allocator)
	}

	// Userinfo as-is (case-sensitive)
	if userinfo, ok := uri.userinfo.?; ok {
		result.userinfo = strings.clone(userinfo, allocator)
	}

	// Host to lowercase
	if host, ok := uri.host.?; ok {
		result.host = strings.to_lower(host, allocator)
	}

	result.port = uri.port
	result.path = strings.clone(uri.path, allocator)

	// Query as-is (case-sensitive)
	if query, ok := uri.query.?; ok {
		result.query = strings.clone(query, allocator)
	}

	// Fragment as-is (case-sensitive)
	if fragment, ok := uri.fragment.?; ok {
		result.fragment = strings.clone(fragment, allocator)
	}

	return result
}
