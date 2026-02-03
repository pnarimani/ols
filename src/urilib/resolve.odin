package urilib

import "core:mem"
import "core:strings"

// resolve resolves a URI reference against a base URI per RFC 3986 Section 5.
// The base URI must be absolute (have a scheme).
// Returns the resolved target URI.
resolve :: proc(base: URI, reference: URI, allocator := context.allocator) -> URI {
	target := make_uri()

	// If the reference has a scheme, it's used as-is (with path normalization)
	if ref_scheme, ok := reference.scheme.?; ok {
		target.scheme = strings.clone(ref_scheme, allocator)
		if userinfo, ok := reference.userinfo.?; ok {
			target.userinfo = strings.clone(userinfo, allocator)
		}
		if host, ok := reference.host.?; ok {
			target.host = strings.clone(host, allocator)
		}
		target.port = reference.port
		target.path = remove_dot_segments(reference.path, allocator)
		if query, ok := reference.query.?; ok {
			target.query = strings.clone(query, allocator)
		}
	} else {
		// Reference has no scheme - resolve relative to base
		if ref_host, ok := reference.host.?; ok {
			// Reference has authority
			if userinfo, ok := reference.userinfo.?; ok {
				target.userinfo = strings.clone(userinfo, allocator)
			}
			target.host = strings.clone(ref_host, allocator)
			target.port = reference.port
			target.path = remove_dot_segments(reference.path, allocator)
			if query, ok := reference.query.?; ok {
				target.query = strings.clone(query, allocator)
			}
		} else {
			// Reference has no authority
			if len(reference.path) == 0 {
				// Empty path - inherit base path
				target.path = strings.clone(base.path, allocator)
				if ref_query, ok := reference.query.?; ok {
					// Reference has query - use it
					target.query = strings.clone(ref_query, allocator)
				} else if base_query, ok := base.query.?; ok {
					// No reference query - inherit base query
					target.query = strings.clone(base_query, allocator)
				}
			} else {
				if strings.has_prefix(reference.path, "/") {
					// Absolute path in reference
					target.path = remove_dot_segments(reference.path, allocator)
				} else {
					// Relative path - merge with base
					merged := merge_paths(base, reference.path, context.temp_allocator)
					target.path = remove_dot_segments(merged, allocator)
				}
				if query, ok := reference.query.?; ok {
					target.query = strings.clone(query, allocator)
				}
			}

			// Inherit authority from base
			if userinfo, ok := base.userinfo.?; ok {
				target.userinfo = strings.clone(userinfo, allocator)
			}
			if host, ok := base.host.?; ok {
				target.host = strings.clone(host, allocator)
			}
			target.port = base.port
		}

		// Inherit scheme from base
		if scheme, ok := base.scheme.?; ok {
			target.scheme = strings.clone(scheme, allocator)
		}
	}

	// Fragment is always from reference (never inherited from base)
	if fragment, ok := reference.fragment.?; ok {
		target.fragment = strings.clone(fragment, allocator)
	}

	return target
}

// merge_paths implements the merge algorithm from RFC 3986 Section 5.2.3.
// It merges a relative path with the base URI's path.
merge_paths :: proc(base: URI, ref_path: string, allocator := context.allocator) -> string {
	// If base has authority and empty path, return "/" + ref_path
	if has_authority(base) && len(base.path) == 0 {
		return strings.concatenate({"/", ref_path}, allocator)
	}

	// Otherwise, return base path up to last "/" + ref_path
	last_slash := -1
	for i := len(base.path) - 1; i >= 0; i -= 1 {
		if base.path[i] == '/' {
			last_slash = i
			break
		}
	}

	if last_slash >= 0 {
		return strings.concatenate({base.path[:last_slash + 1], ref_path}, allocator)
	}

	// No slash in base path - just return ref_path
	return strings.clone(ref_path, allocator)
}

// resolve_string is a convenience function that parses URIs and resolves them.
// Returns the resolved URI as a string.
resolve_string :: proc(base_str: string, reference_str: string, allocator := context.allocator) -> (string, Parse_Error) {
	base, base_err := parse(base_str, context.temp_allocator)
	if base_err != .None {
		return "", base_err
	}

	reference, ref_err := parse_reference(reference_str, context.temp_allocator)
	if ref_err != .None {
		return "", ref_err
	}

	target := resolve(base, reference, context.temp_allocator)
	return to_string(target, allocator), .None
}

// make_relative creates a relative reference from target relative to base.
// This is the inverse of resolve - resolve(base, make_relative(base, target)) == target
// Returns a relative URI that when resolved against base produces target.
make_relative :: proc(base: URI, target: URI, allocator := context.allocator) -> URI {
	result := make_uri()

	// If schemes differ, return target as-is
	base_scheme := get_scheme(base)
	target_scheme := get_scheme(target)
	if !strings.equal_fold(base_scheme, target_scheme) {
		return clone(target, allocator)
	}

	// Schemes match - don't include scheme in result

	// If authorities differ, include authority in result
	base_host := get_host(base)
	target_host := get_host(target)
	base_userinfo := get_userinfo(base)
	target_userinfo := get_userinfo(target)

	if !strings.equal_fold(base_host, target_host) ||
	   base_userinfo != target_userinfo ||
	   base.port != target.port {
		// Different authority - include it
		if userinfo, ok := target.userinfo.?; ok {
			result.userinfo = strings.clone(userinfo, allocator)
		}
		if host, ok := target.host.?; ok {
			result.host = strings.clone(host, allocator)
		}
		result.port = target.port
		result.path = strings.clone(target.path, allocator)
		if query, ok := target.query.?; ok {
			result.query = strings.clone(query, allocator)
		}
		if fragment, ok := target.fragment.?; ok {
			result.fragment = strings.clone(fragment, allocator)
		}
		return result
	}

	// Same authority - compute relative path
	result.path = make_relative_path(base.path, target.path, allocator)

	// Include query if present
	if query, ok := target.query.?; ok {
		result.query = strings.clone(query, allocator)
	}

	// Include fragment if present
	if fragment, ok := target.fragment.?; ok {
		result.fragment = strings.clone(fragment, allocator)
	}

	return result
}

// make_relative_path computes a relative path from base_path to target_path.
@(private)
make_relative_path :: proc(base_path: string, target_path: string, allocator := context.allocator) -> string {
	// Split paths into segments
	base_segments := split_path_segments(base_path, context.temp_allocator)
	target_segments := split_path_segments(target_path, context.temp_allocator)

	// Remove filename from base (keep only directory part)
	if len(base_segments) > 0 {
		pop(&base_segments)
	}

	// Find common prefix
	common := 0
	for common < len(base_segments) && common < len(target_segments) {
		if base_segments[common] != target_segments[common] {
			break
		}
		common += 1
	}

	// Build relative path
	parts := make([dynamic]string, 0, 16, context.temp_allocator)

	// Add ".." for each remaining base segment
	for _ in common ..< len(base_segments) {
		append(&parts, "..")
	}

	// Add remaining target segments
	for i in common ..< len(target_segments) {
		append(&parts, target_segments[i])
	}

	if len(parts) == 0 {
		// Same directory
		if len(target_segments) > 0 {
			return strings.clone(target_segments[len(target_segments) - 1], allocator)
		}
		return strings.clone("", allocator)
	}

	return strings.join(parts[:], "/", allocator)
}

// split_path_segments splits a path into its segments.
@(private)
split_path_segments :: proc(path: string, allocator := context.allocator) -> [dynamic]string {
	result := make([dynamic]string, 0, 8, allocator)

	if len(path) == 0 {
		return result
	}

	remaining := path
	if len(remaining) > 0 && remaining[0] == '/' {
		remaining = remaining[1:]
	}

	for len(remaining) > 0 {
		slash_pos := -1
		for i := 0; i < len(remaining); i += 1 {
			if remaining[i] == '/' {
				slash_pos = i
				break
			}
		}

		if slash_pos >= 0 {
			if slash_pos > 0 {
				append(&result, remaining[:slash_pos])
			}
			remaining = remaining[slash_pos + 1:]
		} else {
			append(&result, remaining)
			break
		}
	}

	return result
}
