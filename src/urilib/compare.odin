package urilib

import "core:strings"

// equal checks if two URIs are identical (simple string comparison of components).
// This is a strict comparison - both URIs must have exactly the same representation.
// For normalization-aware comparison, use equal_normalized.
equal :: proc(a: URI, b: URI) -> bool {
	// Compare schemes
	a_scheme, a_has_scheme := a.scheme.?
	b_scheme, b_has_scheme := b.scheme.?

	if a_has_scheme != b_has_scheme {
		return false
	}
	if a_has_scheme && a_scheme != b_scheme {
		return false
	}

	// Compare userinfo
	a_userinfo, a_has_userinfo := a.userinfo.?
	b_userinfo, b_has_userinfo := b.userinfo.?

	if a_has_userinfo != b_has_userinfo {
		return false
	}
	if a_has_userinfo && a_userinfo != b_userinfo {
		return false
	}

	// Compare hosts
	a_host, a_has_host := a.host.?
	b_host, b_has_host := b.host.?

	if a_has_host != b_has_host {
		return false
	}
	if a_has_host && a_host != b_host {
		return false
	}

	// Compare ports
	a_port, a_has_port := a.port.?
	b_port, b_has_port := b.port.?
	if a_has_port != b_has_port {
		return false
	}
	if a_has_port && a_port != b_port {
		return false
	}

	// Compare paths
	if a.path != b.path {
		return false
	}

	// Compare queries
	a_query, a_has_query := a.query.?
	b_query, b_has_query := b.query.?

	if a_has_query != b_has_query {
		return false
	}
	if a_has_query && a_query != b_query {
		return false
	}

	// Compare fragments
	a_fragment, a_has_fragment := a.fragment.?
	b_fragment, b_has_fragment := b.fragment.?

	if a_has_fragment != b_has_fragment {
		return false
	}
	if a_has_fragment && a_fragment != b_fragment {
		return false
	}

	return true
}

// equal_normalized checks if two URIs are equivalent after normalization.
// This handles case differences in scheme/host, percent-encoding differences,
// default port removal, and path normalization.
// Temporary allocations use context.temp_allocator.
equal_normalized :: proc(a: URI, b: URI) -> bool {
	// Normalize both URIs to temp allocator
	a_norm, a_err := normalize(a, context.temp_allocator)
	if a_err != .None {
		return false
	}

	b_norm, b_err := normalize(b, context.temp_allocator)
	if b_err != .None {
		return false
	}

	return equal(a_norm, b_norm)
}

// equal_string checks if two URI strings are equivalent after parsing and normalization.
equal_string :: proc(a: string, b: string) -> bool {
	a_uri, a_err := parse_reference(a, context.temp_allocator)
	if a_err != .None {
		return false
	}

	b_uri, b_err := parse_reference(b, context.temp_allocator)
	if b_err != .None {
		return false
	}

	return equal_normalized(a_uri, b_uri)
}

// compare performs lexicographic comparison of two URIs.
// Returns Less if a < b, Equal if a == b, Greater if a > b.
// Comparison order: scheme, userinfo, host, port, path, query, fragment.
compare :: proc(a: URI, b: URI) -> Ordering {
	// Compare schemes (case-insensitive)
	a_scheme := get_scheme(a)
	b_scheme := get_scheme(b)

	scheme_cmp := compare_strings_case_insensitive(a_scheme, b_scheme)
	if scheme_cmp != .Equal {
		return scheme_cmp
	}

	// Compare userinfo (case-sensitive)
	a_userinfo := get_userinfo(a)
	b_userinfo := get_userinfo(b)

	userinfo_cmp := compare_strings(a_userinfo, b_userinfo)
	if userinfo_cmp != .Equal {
		return userinfo_cmp
	}

	// Compare hosts (case-insensitive)
	a_host := get_host(a)
	b_host := get_host(b)

	host_cmp := compare_strings_case_insensitive(a_host, b_host)
	if host_cmp != .Equal {
		return host_cmp
	}

	// Compare ports
	a_port, a_has_port := a.port.?
	b_port, b_has_port := b.port.?
	// nil ports sort before present ports
	if !a_has_port && b_has_port {
		return .Less
	}
	if a_has_port && !b_has_port {
		return .Greater
	}
	if a_has_port && b_has_port {
		if a_port < b_port {
			return .Less
		}
		if a_port > b_port {
			return .Greater
		}
	}

	// Compare paths (case-sensitive)
	path_cmp := compare_strings(a.path, b.path)
	if path_cmp != .Equal {
		return path_cmp
	}

	// Compare queries (case-sensitive)
	a_query := get_query(a)
	b_query := get_query(b)

	query_cmp := compare_strings(a_query, b_query)
	if query_cmp != .Equal {
		return query_cmp
	}

	// Compare fragments (case-sensitive)
	a_fragment := get_fragment(a)
	b_fragment := get_fragment(b)

	return compare_strings(a_fragment, b_fragment)
}

// compare_strings performs lexicographic comparison of two strings.
@(private)
compare_strings :: proc(a: string, b: string) -> Ordering {
	min_len := min(len(a), len(b))

	for i := 0; i < min_len; i += 1 {
		if a[i] < b[i] {
			return .Less
		}
		if a[i] > b[i] {
			return .Greater
		}
	}

	if len(a) < len(b) {
		return .Less
	}
	if len(a) > len(b) {
		return .Greater
	}

	return .Equal
}

// compare_strings_case_insensitive performs case-insensitive lexicographic comparison.
@(private)
compare_strings_case_insensitive :: proc(a: string, b: string) -> Ordering {
	min_len := min(len(a), len(b))

	for i := 0; i < min_len; i += 1 {
		a_lower := to_lower_byte(a[i])
		b_lower := to_lower_byte(b[i])

		if a_lower < b_lower {
			return .Less
		}
		if a_lower > b_lower {
			return .Greater
		}
	}

	if len(a) < len(b) {
		return .Less
	}
	if len(a) > len(b) {
		return .Greater
	}

	return .Equal
}

// to_lower_byte converts a single ASCII byte to lowercase.
@(private)
to_lower_byte :: proc(b: u8) -> u8 {
	if b >= 'A' && b <= 'Z' {
		return b + 32 // 'a' - 'A' = 32
	}
	return b
}

// is_same_document checks if a reference is a same-document reference per RFC 3986 Section 4.4.
// A same-document reference is one where the URI, aside from its fragment, is identical to the base.
is_same_document :: proc(base: URI, reference: URI) -> bool {
	// Compare all components except fragment
	// Compare schemes
	a_scheme, a_has_scheme := base.scheme.?
	b_scheme, b_has_scheme := reference.scheme.?

	if a_has_scheme != b_has_scheme {
		return false
	}
	if a_has_scheme && !strings.equal_fold(a_scheme, b_scheme) {
		return false
	}

	// Compare userinfo
	a_userinfo, a_has_userinfo := base.userinfo.?
	b_userinfo, b_has_userinfo := reference.userinfo.?

	if a_has_userinfo != b_has_userinfo {
		return false
	}
	if a_has_userinfo && a_userinfo != b_userinfo {
		return false
	}

	// Compare hosts (case-insensitive)
	a_host, a_has_host := base.host.?
	b_host, b_has_host := reference.host.?

	if a_has_host != b_has_host {
		return false
	}
	if a_has_host && !strings.equal_fold(a_host, b_host) {
		return false
	}

	// Compare ports
	base_port, base_has_port := base.port.?
	ref_port, ref_has_port := reference.port.?
	if base_has_port != ref_has_port {
		return false
	}
	if base_has_port && base_port != ref_port {
		return false
	}

	// Compare paths
	if base.path != reference.path {
		return false
	}

	// Compare queries
	a_query, a_has_query := base.query.?
	b_query, b_has_query := reference.query.?

	if a_has_query != b_has_query {
		return false
	}
	if a_has_query && a_query != b_query {
		return false
	}

	// Fragment is NOT compared - that's what makes it same-document
	return true
}

// is_same_origin checks if two URIs have the same origin.
// Same origin means same scheme, host, and port.
is_same_origin :: proc(a: URI, b: URI) -> bool {
	// Compare schemes (case-insensitive)
	a_scheme, a_has_scheme := a.scheme.?
	b_scheme, b_has_scheme := b.scheme.?

	if a_has_scheme != b_has_scheme {
		return false
	}
	if a_has_scheme && !strings.equal_fold(a_scheme, b_scheme) {
		return false
	}

	// Compare hosts (case-insensitive)
	a_host, a_has_host := a.host.?
	b_host, b_has_host := b.host.?

	if a_has_host != b_has_host {
		return false
	}
	if a_has_host && !strings.equal_fold(a_host, b_host) {
		return false
	}

	// Compare ports (considering default ports)
	a_port := get_effective_port(a)
	b_port := get_effective_port(b)

	return a_port == b_port
}

// get_effective_port returns the port to use, considering default ports.
// Returns the explicit port if set, or the default port for the scheme, or -1.
get_effective_port :: proc(uri: URI) -> int {
	if port, has_port := uri.port.?; has_port {
		return port
	}

	if scheme, ok := uri.scheme.?; ok {
		scheme_lower := strings.to_lower(scheme, context.temp_allocator)
		if default_port, has_default := DEFAULT_PORTS[scheme_lower]; has_default {
			return default_port
		}
	}

	return -1
}
