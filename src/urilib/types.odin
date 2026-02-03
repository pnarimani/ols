#+feature dynamic-literals
package urilib

// URI represents a parsed Uniform Resource Identifier per RFC 3986.
// The general form is: scheme://userinfo@host:port/path?query#fragment
URI :: struct {
	scheme:   Maybe(string), // e.g., "http", "https", "ftp"
	userinfo: Maybe(string), // e.g., "user:password" (deprecated but supported)
	host:     Maybe(string), // e.g., "example.com", "192.168.1.1", "[::1]"
	port:     Maybe(int),    // nil if not specified, otherwise the port number
	path:     string,        // e.g., "/path/to/resource" (always present, may be empty)
	query:    Maybe(string), // e.g., "key=value&foo=bar" (without leading '?')
	fragment: Maybe(string), // e.g., "section1" (without leading '#')
}

// Parse_Error represents errors that can occur during URI parsing or decoding.
Parse_Error :: enum {
	None,
	Invalid_Percent_Encoding, // Malformed %XX sequence
	Invalid_UTF8,             // Decoded bytes are not valid UTF-8
	Invalid_Port,             // Port is not a valid number or out of range
	Invalid_Scheme,           // Scheme contains invalid characters
	Invalid_Host,             // Host contains invalid characters
	Invalid_IPv6,             // IPv6 address is malformed
	Unexpected_End,           // Unexpected end of input
}

// Ordering for comparison results
Ordering :: enum {
	Less    = -1,
	Equal   = 0,
	Greater = 1,
}

// Character classification lookup tables for O(1) checks.
// These follow RFC 3986 definitions.

// UNRESERVED = ALPHA / DIGIT / "-" / "." / "_" / "~"
// Characters that can appear in any URI component without encoding
@(private = "package")
UNRESERVED: [256]bool = #partial {
	'A' = true, 'B' = true, 'C' = true, 'D' = true, 'E' = true, 'F' = true,
	'G' = true, 'H' = true, 'I' = true, 'J' = true, 'K' = true, 'L' = true,
	'M' = true, 'N' = true, 'O' = true, 'P' = true, 'Q' = true, 'R' = true,
	'S' = true, 'T' = true, 'U' = true, 'V' = true, 'W' = true, 'X' = true,
	'Y' = true, 'Z' = true,
	'a' = true, 'b' = true, 'c' = true, 'd' = true, 'e' = true, 'f' = true,
	'g' = true, 'h' = true, 'i' = true, 'j' = true, 'k' = true, 'l' = true,
	'm' = true, 'n' = true, 'o' = true, 'p' = true, 'q' = true, 'r' = true,
	's' = true, 't' = true, 'u' = true, 'v' = true, 'w' = true, 'x' = true,
	'y' = true, 'z' = true,
	'0' = true, '1' = true, '2' = true, '3' = true, '4' = true,
	'5' = true, '6' = true, '7' = true, '8' = true, '9' = true,
	'-' = true, '.' = true, '_' = true, '~' = true,
}

// GEN_DELIMS = ":" / "/" / "?" / "#" / "[" / "]" / "@"
// Generic delimiter characters that separate URI components
@(private = "package")
GEN_DELIMS: [256]bool = #partial {
	':' = true, '/' = true, '?' = true, '#' = true,
	'[' = true, ']' = true, '@' = true,
}

// SUB_DELIMS = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
// Sub-delimiter characters used within components
@(private = "package")
SUB_DELIMS: [256]bool = #partial {
	'!' = true, '$' = true, '&' = true, '\'' = true,
	'(' = true, ')' = true, '*' = true, '+' = true,
	',' = true, ';' = true, '=' = true,
}

// SCHEME_CHARS = ALPHA / DIGIT / "+" / "-" / "."
// Characters allowed in scheme (after the first character which must be ALPHA)
@(private = "package")
SCHEME_CHARS: [256]bool = #partial {
	'A' = true, 'B' = true, 'C' = true, 'D' = true, 'E' = true, 'F' = true,
	'G' = true, 'H' = true, 'I' = true, 'J' = true, 'K' = true, 'L' = true,
	'M' = true, 'N' = true, 'O' = true, 'P' = true, 'Q' = true, 'R' = true,
	'S' = true, 'T' = true, 'U' = true, 'V' = true, 'W' = true, 'X' = true,
	'Y' = true, 'Z' = true,
	'a' = true, 'b' = true, 'c' = true, 'd' = true, 'e' = true, 'f' = true,
	'g' = true, 'h' = true, 'i' = true, 'j' = true, 'k' = true, 'l' = true,
	'm' = true, 'n' = true, 'o' = true, 'p' = true, 'q' = true, 'r' = true,
	's' = true, 't' = true, 'u' = true, 'v' = true, 'w' = true, 'x' = true,
	'y' = true, 'z' = true,
	'0' = true, '1' = true, '2' = true, '3' = true, '4' = true,
	'5' = true, '6' = true, '7' = true, '8' = true, '9' = true,
	'+' = true, '-' = true, '.' = true,
}

// HEXDIG for percent-encoding
@(private = "package")
HEXDIG: [256]bool = #partial {
	'0' = true, '1' = true, '2' = true, '3' = true, '4' = true,
	'5' = true, '6' = true, '7' = true, '8' = true, '9' = true,
	'A' = true, 'B' = true, 'C' = true, 'D' = true, 'E' = true, 'F' = true,
	'a' = true, 'b' = true, 'c' = true, 'd' = true, 'e' = true, 'f' = true,
}

// ALPHA characters
@(private = "package")
ALPHA: [256]bool = #partial {
	'A' = true, 'B' = true, 'C' = true, 'D' = true, 'E' = true, 'F' = true,
	'G' = true, 'H' = true, 'I' = true, 'J' = true, 'K' = true, 'L' = true,
	'M' = true, 'N' = true, 'O' = true, 'P' = true, 'Q' = true, 'R' = true,
	'S' = true, 'T' = true, 'U' = true, 'V' = true, 'W' = true, 'X' = true,
	'Y' = true, 'Z' = true,
	'a' = true, 'b' = true, 'c' = true, 'd' = true, 'e' = true, 'f' = true,
	'g' = true, 'h' = true, 'i' = true, 'j' = true, 'k' = true, 'l' = true,
	'm' = true, 'n' = true, 'o' = true, 'p' = true, 'q' = true, 'r' = true,
	's' = true, 't' = true, 'u' = true, 'v' = true, 'w' = true, 'x' = true,
	'y' = true, 'z' = true,
}

// DIGIT characters
@(private = "package")
DIGIT: [256]bool = #partial {
	'0' = true, '1' = true, '2' = true, '3' = true, '4' = true,
	'5' = true, '6' = true, '7' = true, '8' = true, '9' = true,
}

// Hex value lookup table for decoding
@(private = "package")
HEX_VALUES: [256]u8 = #partial {
	'0' = 0,  '1' = 1,  '2' = 2,  '3' = 3,  '4' = 4,
	'5' = 5,  '6' = 6,  '7' = 7,  '8' = 8,  '9' = 9,
	'A' = 10, 'B' = 11, 'C' = 12, 'D' = 13, 'E' = 14, 'F' = 15,
	'a' = 10, 'b' = 11, 'c' = 12, 'd' = 13, 'e' = 14, 'f' = 15,
}

// Default ports for common schemes (for normalization)
@(private = "package")
DEFAULT_PORTS: map[string]int = {
	"http"   = 80,
	"https"  = 443,
	"ftp"    = 21,
	"ssh"    = 22,
	"telnet" = 23,
	"ws"     = 80,
	"wss"    = 443,
}

// Helper to check if a byte is in a character set
@(private = "package")
is_in_set :: #force_inline proc(b: u8, set: [256]bool) -> bool {
	return set[b]
}

// Helper to check if a byte is unreserved
@(private = "package")
is_unreserved :: #force_inline proc(b: u8) -> bool {
	return UNRESERVED[b]
}

// Helper to check if a byte is a hex digit
@(private = "package")
is_hexdig :: #force_inline proc(b: u8) -> bool {
	return HEXDIG[b]
}

// Helper to get hex value of a character
@(private = "package")
hex_value :: #force_inline proc(b: u8) -> u8 {
	return HEX_VALUES[b]
}

// Create an empty URI with default values
make_uri :: proc() -> URI {
	return URI{
		scheme   = nil,
		userinfo = nil,
		host     = nil,
		port     = nil,
		path     = "",
		query    = nil,
		fragment = nil,
	}
}

// Check if URI has an authority component (host is present)
has_authority :: proc(uri: URI) -> bool {
	return uri.host != nil
}

// Check if URI is absolute (has a scheme)
is_absolute :: proc(uri: URI) -> bool {
	return uri.scheme != nil
}

// Check if URI is a relative reference (no scheme)
is_relative :: proc(uri: URI) -> bool {
	return uri.scheme == nil
}
