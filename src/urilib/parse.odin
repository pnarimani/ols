package urilib

import "core:mem"
import "core:strconv"
import "core:strings"

// parse parses an absolute URI string into its components.
// The URI must have a scheme. For relative references, use parse_reference.
// Returns the parsed URI and any error encountered.
parse :: proc(uri_string: string, allocator := context.allocator) -> (URI, Parse_Error) {
	result, err := parse_reference(uri_string, allocator)
	if err != .None {
		return result, err
	}

	// An absolute URI must have a scheme
	if result.scheme == nil {
		destroy(&result, allocator)
		return make_uri(), .Invalid_Scheme
	}

	return result, .None
}

// parse_reference parses a URI reference which may be absolute or relative.
// This implements the RFC 3986 grammar for URI-reference = URI / relative-ref
parse_reference :: proc(uri_string: string, allocator := context.allocator) -> (URI, Parse_Error) {
	result := make_uri()
	remaining := uri_string

	// Try to extract scheme (must start with ALPHA)
	scheme_end := find_scheme_end(remaining)
	if scheme_end > 0 {
		scheme_str := remaining[:scheme_end]
		// Validate scheme characters
		if !validate_scheme(scheme_str) {
			return result, .Invalid_Scheme
		}
		result.scheme = strings.clone(scheme_str, allocator)
		remaining = remaining[scheme_end + 1:] // Skip the ':'
	}

	// Check for authority (starts with "//")
	if strings.has_prefix(remaining, "//") {
		remaining = remaining[2:]

		// Find end of authority (next '/', '?', '#', or end)
		auth_end := len(remaining)
		for i := 0; i < len(remaining); i += 1 {
			if remaining[i] == '/' || remaining[i] == '?' || remaining[i] == '#' {
				auth_end = i
				break
			}
		}

		authority := remaining[:auth_end]
		remaining = remaining[auth_end:]

		// Parse authority components
		err := parse_authority(authority, &result, allocator)
		if err != .None {
			destroy(&result, allocator)
			return make_uri(), err
		}
	}

	// Extract path (up to '?' or '#' or end)
	path_end := len(remaining)
	for i := 0; i < len(remaining); i += 1 {
		if remaining[i] == '?' || remaining[i] == '#' {
			path_end = i
			break
		}
	}

	result.path = strings.clone(remaining[:path_end], allocator)
	remaining = remaining[path_end:]

	// Extract query (after '?' up to '#' or end)
	if len(remaining) > 0 && remaining[0] == '?' {
		remaining = remaining[1:]
		query_end := len(remaining)
		for i := 0; i < len(remaining); i += 1 {
			if remaining[i] == '#' {
				query_end = i
				break
			}
		}
		result.query = strings.clone(remaining[:query_end], allocator)
		remaining = remaining[query_end:]
	}

	// Extract fragment (after '#')
	if len(remaining) > 0 && remaining[0] == '#' {
		result.fragment = strings.clone(remaining[1:], allocator)
	}

	return result, .None
}

// find_scheme_end finds the position of ':' that ends a scheme.
// Returns -1 if no valid scheme is found.
// A scheme must start with ALPHA and contain only ALPHA / DIGIT / "+" / "-" / "."
@(private)
find_scheme_end :: proc(s: string) -> int {
	if len(s) == 0 {
		return -1
	}

	// First character must be ALPHA
	if !ALPHA[s[0]] {
		return -1
	}

	for i := 1; i < len(s); i += 1 {
		c := s[i]
		if c == ':' {
			return i
		}
		if !SCHEME_CHARS[c] {
			return -1
		}
	}

	return -1
}

// validate_scheme checks if a string is a valid scheme.
@(private)
validate_scheme :: proc(s: string) -> bool {
	if len(s) == 0 {
		return false
	}

	if !ALPHA[s[0]] {
		return false
	}

	for i := 1; i < len(s); i += 1 {
		if !SCHEME_CHARS[s[i]] {
			return false
		}
	}

	return true
}

// parse_authority parses the authority component into userinfo, host, and port.
// authority = [ userinfo "@" ] host [ ":" port ]
@(private)
parse_authority :: proc(authority: string, result: ^URI, allocator := context.allocator) -> Parse_Error {
	remaining := authority

	// Look for userinfo (before '@')
	// We need to find the last '@' because userinfo can contain '@' if percent-encoded
	// But actually, '@' in userinfo must be percent-encoded, so first '@' delimits
	at_pos := -1
	for i := 0; i < len(remaining); i += 1 {
		if remaining[i] == '@' {
			at_pos = i
			break
		}
		// Skip over IPv6 brackets to avoid confusion with '@' inside
		if remaining[i] == '[' {
			// Find closing bracket
			for j := i + 1; j < len(remaining); j += 1 {
				if remaining[j] == ']' {
					i = j
					break
				}
			}
		}
	}

	if at_pos >= 0 {
		result.userinfo = strings.clone(remaining[:at_pos], allocator)
		remaining = remaining[at_pos + 1:]
	}

	// Now parse host and port
	// host can be: IP-literal (starts with '['), IPv4address, or reg-name
	if len(remaining) > 0 && remaining[0] == '[' {
		// IPv6 or IPvFuture literal
		bracket_end := -1
		for i := 1; i < len(remaining); i += 1 {
			if remaining[i] == ']' {
				bracket_end = i
				break
			}
		}

		if bracket_end < 0 {
			return .Invalid_IPv6
		}

		// Validate IPv6 content (basic check - just ensure it's present)
		ipv6_content := remaining[1:bracket_end]
		if len(ipv6_content) == 0 {
			return .Invalid_IPv6
		}

		result.host = strings.clone(remaining[:bracket_end + 1], allocator)
		remaining = remaining[bracket_end + 1:]

		// Check for port after IPv6
		if len(remaining) > 0 {
			if remaining[0] == ':' {
				err := parse_port(remaining[1:], result, allocator)
				if err != .None {
					return err
				}
			} else {
				// Invalid character after IPv6 bracket
				return .Invalid_Host
			}
		}
	} else {
		// Regular host (IPv4 or reg-name)
		// Find ':' for port (last ':' because reg-name can have encoded ':')
		// Actually, unencoded ':' in reg-name is not allowed, so first ':' is port delimiter
		colon_pos := -1
		for i := 0; i < len(remaining); i += 1 {
			if remaining[i] == ':' {
				colon_pos = i
				break
			}
		}

		if colon_pos >= 0 {
			result.host = strings.clone(remaining[:colon_pos], allocator)
			err := parse_port(remaining[colon_pos + 1:], result, allocator)
			if err != .None {
				return err
			}
		} else {
			if len(remaining) > 0 {
				result.host = strings.clone(remaining, allocator)
			} else {
				// Empty host is valid (e.g., file:///path)
				result.host = strings.clone("", allocator)
			}
		}
	}

	return .None
}

// parse_port parses the port number from a string.
@(private)
parse_port :: proc(port_str: string, result: ^URI, allocator := context.allocator) -> Parse_Error {
	if len(port_str) == 0 {
		// Empty port is valid, means no port specified
		return .None
	}

	// Validate all characters are digits
	for b in transmute([]u8)port_str {
		if !DIGIT[b] {
			return .Invalid_Port
		}
	}

	// Parse the number
	port_value, ok := strconv.parse_int(port_str)
	if !ok {
		return .Invalid_Port
	}

	// Validate port range (0-65535)
	if port_value < 0 || port_value > 65535 {
		return .Invalid_Port
	}

	result.port = port_value
	return .None
}

// split_once splits a string at the first occurrence of a delimiter.
// Returns the parts before and after the delimiter, and whether it was found.
@(private)
split_once :: proc(s: string, delim: u8) -> (before: string, after: string, found: bool) {
	for i := 0; i < len(s); i += 1 {
		if s[i] == delim {
			return s[:i], s[i + 1:], true
		}
	}
	return s, "", false
}

// Get the scheme as a string, or empty string if not present
get_scheme :: proc(uri: URI) -> string {
	if s, ok := uri.scheme.?; ok {
		return s
	}
	return ""
}

// Get the host as a string, or empty string if not present
get_host :: proc(uri: URI) -> string {
	if h, ok := uri.host.?; ok {
		return h
	}
	return ""
}

// Get the userinfo as a string, or empty string if not present
get_userinfo :: proc(uri: URI) -> string {
	if u, ok := uri.userinfo.?; ok {
		return u
	}
	return ""
}

// Get the query as a string, or empty string if not present
get_query :: proc(uri: URI) -> string {
	if q, ok := uri.query.?; ok {
		return q
	}
	return ""
}

// Get the fragment as a string, or empty string if not present
get_fragment :: proc(uri: URI) -> string {
	if f, ok := uri.fragment.?; ok {
		return f
	}
	return ""
}
