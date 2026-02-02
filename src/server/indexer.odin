package server

import "core:log"
import "core:strings"

import "src:analysis"

FuzzyResult :: struct {
	symbol: analysis.Symbol,
	score:  f32,
}

should_skip_private_symbol :: proc(symbol: analysis.Symbol, current_pkg, current_file: string) -> bool {
	if .PrivateFile not_in symbol.flags && .PrivatePackage not_in symbol.flags {
		return false
	}

	if current_file == "" {
		return false
	}

	symbol_file := strings.trim_prefix(symbol.uri, "file://")
	current_file := strings.trim_prefix(current_file, "file://")
	if .PrivateFile in symbol.flags && symbol_file != current_file {
		return true
	}

	if .PrivatePackage in symbol.flags && current_pkg != symbol.pkg {
		return true
	}
	return false
}

lookup :: proc(symbols: ^analysis.SymbolCollection, name: string, pkg: string, current_file: string, loc := #caller_location) -> (analysis.Symbol, bool) {
	if name == "" || symbols == nil {
		return {}, false
	}

	if _pkg, ok := &symbols.packages[pkg]; ok {
		if symbol, ok := _pkg.symbols[name]; ok {
			current_pkg := get_package_from_filepath(current_file)
			if should_skip_private_symbol(symbol, current_pkg, current_file) {
				return {}, false
			}
			return symbol, true
		}
	}

	return {}, false
}

fuzzy_search :: proc(
	symbols: ^analysis.SymbolCollection,
	name: string,
	pkgs: []string,
	current_file: string,
	resolve_fields := false,
	limit := 0,
) -> (
	[]FuzzyResult,
	bool,
) {
	if symbols == nil {
		return {}, false
	}
	results, ok := symbol_collection_fuzzy_search(symbols, name, pkgs, current_file, resolve_fields, limit = limit)
	if !ok {
		return {}, false
	}
	return results[:], true
}
