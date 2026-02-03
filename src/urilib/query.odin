package urilib

import "core:mem"
import "core:strings"

// Query_Params is a map of query parameter names to their values.
// Multiple values per key are supported (common in web forms).
Query_Params :: map[string][dynamic]string

// parse_query_params parses a query string into a map of key-value pairs.
// Handles standard "key=value&key2=value2" format.
// Decodes percent-encoded characters in both keys and values.
// Supports multiple values per key (returns dynamic array per key).
parse_query_params :: proc(query: string, allocator := context.allocator) -> (Query_Params, Parse_Error) {
	result := make(Query_Params, allocator = allocator)

	if len(query) == 0 {
		return result, .None
	}

	remaining := query
	for len(remaining) > 0 {
		// Find next '&' or end
		amp_pos := -1
		for i := 0; i < len(remaining); i += 1 {
			if remaining[i] == '&' {
				amp_pos = i
				break
			}
		}

		pair: string
		if amp_pos >= 0 {
			pair = remaining[:amp_pos]
			remaining = remaining[amp_pos + 1:]
		} else {
			pair = remaining
			remaining = ""
		}

		if len(pair) == 0 {
			continue
		}

		// Split by '='
		eq_pos := -1
		for i := 0; i < len(pair); i += 1 {
			if pair[i] == '=' {
				eq_pos = i
				break
			}
		}

		key_encoded: string
		value_encoded: string

		if eq_pos >= 0 {
			key_encoded = pair[:eq_pos]
			value_encoded = pair[eq_pos + 1:]
		} else {
			// No '=' means key with empty value
			key_encoded = pair
			value_encoded = ""
		}

		// Decode key and value (using form decoding for + as space)
		key, key_err := decode_form_component(key_encoded, context.temp_allocator)
		if key_err != .None {
			destroy_query_params(&result, allocator)
			return make(Query_Params, allocator = allocator), key_err
		}

		value, value_err := decode_form_component(value_encoded, context.temp_allocator)
		if value_err != .None {
			destroy_query_params(&result, allocator)
			return make(Query_Params, allocator = allocator), value_err
		}

		// Clone to target allocator and add to result
		key_cloned := strings.clone(key, allocator)
		value_cloned := strings.clone(value, allocator)

		if key_cloned not_in result {
			result[key_cloned] = make([dynamic]string, allocator = allocator)
		}
		append(&result[key_cloned], value_cloned)
	}

	return result, .None
}

// build_query_params builds a query string from a map of parameters.
// Keys and values are percent-encoded for safe inclusion in a URI.
// Multiple values per key are joined with '&'.
build_query_params :: proc(params: Query_Params, allocator := context.allocator) -> string {
	if len(params) == 0 {
		return strings.clone("", allocator)
	}

	builder := strings.builder_make(context.temp_allocator)
	first := true

	for key, values in params {
		key_encoded := encode_form_component(key, context.temp_allocator)

		for value in values {
			if !first {
				strings.write_byte(&builder, '&')
			}
			first = false

			strings.write_string(&builder, key_encoded)
			strings.write_byte(&builder, '=')
			strings.write_string(&builder, encode_form_component(value, context.temp_allocator))
		}
	}

	return strings.clone(strings.to_string(builder), allocator)
}

// build_query_params_simple builds a query string from simple key-value pairs.
// Each key has exactly one value.
build_query_params_simple :: proc(params: map[string]string, allocator := context.allocator) -> string {
	if len(params) == 0 {
		return strings.clone("", allocator)
	}

	builder := strings.builder_make(context.temp_allocator)
	first := true

	for key, value in params {
		if !first {
			strings.write_byte(&builder, '&')
		}
		first = false

		strings.write_string(&builder, encode_form_component(key, context.temp_allocator))
		strings.write_byte(&builder, '=')
		strings.write_string(&builder, encode_form_component(value, context.temp_allocator))
	}

	return strings.clone(strings.to_string(builder), allocator)
}

// encode_form_component encodes a string for use in application/x-www-form-urlencoded.
// This is similar to encode_query_component but also encodes space as '+' instead of '%20'.
encode_form_component :: proc(value: string, allocator := context.allocator) -> string {
	// First encode with unreserved set
	encoded := encode_with_allowed(value, UNRESERVED, context.temp_allocator)

	// Then replace %20 with + (space encoding for forms)
	// Actually, for efficiency, let's do this in one pass
	// Re-implement with space -> + handling

	// Count result length
	result_len := 0
	for b in transmute([]u8)value {
		if UNRESERVED[b] {
			result_len += 1
		} else if b == ' ' {
			result_len += 1 // '+' instead of %20
		} else {
			result_len += 3 // %XX
		}
	}

	// If nothing changes, just clone
	if result_len == len(value) {
		return strings.clone(value, allocator)
	}

	// Allocate and fill
	result := make([]u8, result_len, allocator)
	idx := 0

	for b in transmute([]u8)value {
		if UNRESERVED[b] {
			result[idx] = b
			idx += 1
		} else if b == ' ' {
			result[idx] = '+'
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

// decode_form_component decodes a application/x-www-form-urlencoded string.
// This handles both percent-encoding and '+' as space.
decode_form_component :: proc(value: string, allocator := context.allocator) -> (string, Parse_Error) {
	// Check if we need to do any decoding
	needs_decode := false
	for b in transmute([]u8)value {
		if b == '%' || b == '+' {
			needs_decode = true
			break
		}
	}

	if !needs_decode {
		return strings.clone(value, allocator), .None
	}

	// Decode
	temp_result := make([dynamic]u8, 0, len(value), context.temp_allocator)

	data := transmute([]u8)value
	i := 0
	for i < len(data) {
		if data[i] == '+' {
			// '+' is space in form encoding
			append(&temp_result, ' ')
			i += 1
		} else if data[i] == '%' {
			// Percent-encoded byte
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

	return strings.clone(string(temp_result[:]), allocator), .None
}

// get_query_param returns the first value for a query parameter, or nil if not found.
get_query_param :: proc(params: Query_Params, key: string) -> Maybe(string) {
	if values, ok := params[key]; ok {
		if len(values) > 0 {
			return values[0]
		}
	}
	return nil
}

// get_query_params returns all values for a query parameter, or empty slice if not found.
get_query_params :: proc(params: Query_Params, key: string) -> []string {
	if values, ok := params[key]; ok {
		return values[:]
	}
	return {}
}

// has_query_param checks if a query parameter exists.
has_query_param :: proc(params: Query_Params, key: string) -> bool {
	return key in params
}

// set_query_param sets a single value for a query parameter (replacing any existing values).
set_query_param :: proc(params: ^Query_Params, key: string, value: string, allocator := context.allocator) {
	key_cloned := strings.clone(key, allocator)
	value_cloned := strings.clone(value, allocator)

	if key_cloned in params^ {
		// Clear existing values
		for v in params^[key_cloned] {
			delete(v, allocator)
		}
		clear(&params^[key_cloned])
	} else {
		params^[key_cloned] = make([dynamic]string, allocator = allocator)
	}

	append(&params^[key_cloned], value_cloned)
}

// add_query_param adds a value to a query parameter (keeps existing values).
add_query_param :: proc(params: ^Query_Params, key: string, value: string, allocator := context.allocator) {
	key_cloned := strings.clone(key, allocator)
	value_cloned := strings.clone(value, allocator)

	if key_cloned not_in params^ {
		params^[key_cloned] = make([dynamic]string, allocator = allocator)
	}

	append(&params^[key_cloned], value_cloned)
}

// remove_query_param removes a query parameter and all its values.
remove_query_param :: proc(params: ^Query_Params, key: string, allocator := context.allocator) {
	if values, ok := params^[key]; ok {
		for v in values {
			delete(v, allocator)
		}
		delete(values)
		delete_key(params, key)
	}
}

// destroy_query_params frees all memory associated with query params.
destroy_query_params :: proc(params: ^Query_Params, allocator := context.allocator) {
	for key, values in params^ {
		for v in values {
			delete(v, allocator)
		}
		delete(values)
		delete(key, allocator)
	}
	delete(params^)
}

// clone_query_params creates a deep copy of query params.
clone_query_params :: proc(params: Query_Params, allocator := context.allocator) -> Query_Params {
	result := make(Query_Params, allocator = allocator)

	for key, values in params {
		key_cloned := strings.clone(key, allocator)
		result[key_cloned] = make([dynamic]string, allocator = allocator)

		for v in values {
			append(&result[key_cloned], strings.clone(v, allocator))
		}
	}

	return result
}
