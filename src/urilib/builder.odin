package urilib

import "core:mem"
import "core:strconv"
import "core:strings"

// to_string recomposes a URI from its components per RFC 3986 Section 5.3.
// This is the inverse of parse.
to_string :: proc(uri: URI, allocator := context.allocator) -> string {
	builder := strings.builder_make(context.temp_allocator)

	// Scheme
	if scheme, ok := uri.scheme.?; ok {
		strings.write_string(&builder, scheme)
		strings.write_byte(&builder, ':')
	}

	// Authority
	if has_authority(uri) {
		strings.write_string(&builder, "//")

		// Userinfo
		if userinfo, ok := uri.userinfo.?; ok {
			strings.write_string(&builder, userinfo)
			strings.write_byte(&builder, '@')
		}

		// Host
		if host, ok := uri.host.?; ok {
			strings.write_string(&builder, host)
		}

		// Port
		if port, has_port := uri.port.?; has_port {
			strings.write_byte(&builder, ':')
			strings.write_int(&builder, port)
		}
	}

	// Path
	strings.write_string(&builder, uri.path)

	// Query
	if query, ok := uri.query.?; ok {
		strings.write_byte(&builder, '?')
		strings.write_string(&builder, query)
	}

	// Fragment
	if fragment, ok := uri.fragment.?; ok {
		strings.write_byte(&builder, '#')
		strings.write_string(&builder, fragment)
	}

	return strings.clone(strings.to_string(builder), allocator)
}

// Build_Options for configuring URI construction
Build_Options :: struct {
	encode_path:     bool, // Whether to percent-encode the path
	encode_query:    bool, // Whether to percent-encode the query
	encode_fragment: bool, // Whether to percent-encode the fragment
	encode_userinfo: bool, // Whether to percent-encode the userinfo
}

// Default build options - encode everything
DEFAULT_BUILD_OPTIONS :: Build_Options{
	encode_path     = true,
	encode_query    = true,
	encode_fragment = true,
	encode_userinfo = true,
}

// build constructs a URI from individual components with optional encoding.
// Components are encoded according to their role in the URI.
build :: proc(
	scheme: Maybe(string) = nil,
	userinfo: Maybe(string) = nil,
	host: Maybe(string) = nil,
	port: Maybe(int) = nil,
	path: string = "",
	query: Maybe(string) = nil,
	fragment: Maybe(string) = nil,
	options: Build_Options = DEFAULT_BUILD_OPTIONS,
	allocator := context.allocator,
) -> string {
	uri := make_uri()
	defer destroy(&uri, context.temp_allocator)

	// Set scheme (no encoding needed - must be valid)
	if s, ok := scheme.?; ok {
		uri.scheme = strings.clone(s, context.temp_allocator)
	}

	// Set userinfo (optionally encoded)
	if u, ok := userinfo.?; ok {
		if options.encode_userinfo {
			uri.userinfo = encode_userinfo(u, context.temp_allocator)
		} else {
			uri.userinfo = strings.clone(u, context.temp_allocator)
		}
	}

	// Set host (encode if reg-name, preserve if IPv6)
	if h, ok := host.?; ok {
		uri.host = encode_host(h, context.temp_allocator)
	}

	// Set port
	uri.port = port

	// Set path (optionally encoded)
	if options.encode_path {
		uri.path = encode_path(path, context.temp_allocator)
	} else {
		uri.path = strings.clone(path, context.temp_allocator)
	}

	// Set query (optionally encoded)
	if q, ok := query.?; ok {
		if options.encode_query {
			uri.query = encode_query(q, context.temp_allocator)
		} else {
			uri.query = strings.clone(q, context.temp_allocator)
		}
	}

	// Set fragment (optionally encoded)
	if f, ok := fragment.?; ok {
		if options.encode_fragment {
			uri.fragment = encode_fragment(f, context.temp_allocator)
		} else {
			uri.fragment = strings.clone(f, context.temp_allocator)
		}
	}

	return to_string(uri, allocator)
}

// build_simple is a convenience function for building common URIs.
// Automatically encodes all components.
build_simple :: proc(
	scheme: string,
	host: string,
	path: string = "/",
	query: Maybe(string) = nil,
	fragment: Maybe(string) = nil,
	allocator := context.allocator,
) -> string {
	return build(
		scheme = scheme,
		host = host,
		path = path,
		query = query,
		fragment = fragment,
		allocator = allocator,
	)
}

// destroy frees all allocated strings in a URI.
// After calling destroy, the URI should not be used.
destroy :: proc(uri: ^URI, allocator := context.allocator) {
	if scheme, ok := uri.scheme.?; ok {
		delete(scheme, allocator)
		uri.scheme = nil
	}

	if userinfo, ok := uri.userinfo.?; ok {
		delete(userinfo, allocator)
		uri.userinfo = nil
	}

	if host, ok := uri.host.?; ok {
		delete(host, allocator)
		uri.host = nil
	}

	if len(uri.path) > 0 {
		delete(uri.path, allocator)
		uri.path = ""
	}

	if query, ok := uri.query.?; ok {
		delete(query, allocator)
		uri.query = nil
	}

	if fragment, ok := uri.fragment.?; ok {
		delete(fragment, allocator)
		uri.fragment = nil
	}

	uri.port = nil
}

// clone creates a deep copy of a URI.
// All strings are cloned to the specified allocator.
clone :: proc(uri: URI, allocator := context.allocator) -> URI {
	result := make_uri()

	if scheme, ok := uri.scheme.?; ok {
		result.scheme = strings.clone(scheme, allocator)
	}

	if userinfo, ok := uri.userinfo.?; ok {
		result.userinfo = strings.clone(userinfo, allocator)
	}

	if host, ok := uri.host.?; ok {
		result.host = strings.clone(host, allocator)
	}

	result.port = uri.port
	result.path = strings.clone(uri.path, allocator)

	if query, ok := uri.query.?; ok {
		result.query = strings.clone(query, allocator)
	}

	if fragment, ok := uri.fragment.?; ok {
		result.fragment = strings.clone(fragment, allocator)
	}

	return result
}

// with_scheme returns a copy of the URI with a new scheme.
with_scheme :: proc(uri: URI, scheme: string, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	if old_scheme, ok := result.scheme.?; ok {
		delete(old_scheme, allocator)
	}
	result.scheme = strings.clone(scheme, allocator)
	return result
}

// with_host returns a copy of the URI with a new host.
with_host :: proc(uri: URI, host: string, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	if old_host, ok := result.host.?; ok {
		delete(old_host, allocator)
	}
	result.host = encode_host(host, allocator)
	return result
}

// with_port returns a copy of the URI with a new port.
with_port :: proc(uri: URI, port: int, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	result.port = port
	return result
}

// with_path returns a copy of the URI with a new path.
with_path :: proc(uri: URI, path: string, encode := true, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	if len(result.path) > 0 {
		delete(result.path, allocator)
	}
	if encode {
		result.path = encode_path(path, allocator)
	} else {
		result.path = strings.clone(path, allocator)
	}
	return result
}

// with_query returns a copy of the URI with a new query.
with_query :: proc(uri: URI, query: string, encode := true, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	if old_query, ok := result.query.?; ok {
		delete(old_query, allocator)
	}
	if encode {
		result.query = encode_query(query, allocator)
	} else {
		result.query = strings.clone(query, allocator)
	}
	return result
}

// with_fragment returns a copy of the URI with a new fragment.
with_fragment :: proc(uri: URI, fragment: string, encode := true, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	if old_fragment, ok := result.fragment.?; ok {
		delete(old_fragment, allocator)
	}
	if encode {
		result.fragment = encode_fragment(fragment, allocator)
	} else {
		result.fragment = strings.clone(fragment, allocator)
	}
	return result
}

// without_query returns a copy of the URI with the query removed.
without_query :: proc(uri: URI, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	if old_query, ok := result.query.?; ok {
		delete(old_query, allocator)
	}
	result.query = nil
	return result
}

// without_fragment returns a copy of the URI with the fragment removed.
without_fragment :: proc(uri: URI, allocator := context.allocator) -> URI {
	result := clone(uri, allocator)
	if old_fragment, ok := result.fragment.?; ok {
		delete(old_fragment, allocator)
	}
	result.fragment = nil
	return result
}
