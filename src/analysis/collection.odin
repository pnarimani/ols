package analysis

import "core:odin/ast"
import "core:strings"

import "src:common"

// ============================================================================
// String interning
// ============================================================================

get_index_unique_string :: proc {
	get_index_unique_string_collection,
	get_index_unique_string_collection_raw,
}

@(private = "package")
get_index_unique_string_collection :: proc(collection: ^SymbolCollection, s: string) -> string {
	return get_index_unique_string_collection_raw(&collection.unique_strings, s)
}

get_index_unique_string_collection_raw :: proc(unique_strings: ^map[string]string, s: string) -> string {
	if _, ok := unique_strings[s]; !ok {
		str := strings.clone(s)
		unique_strings[str] = str
	}

	return unique_strings[s]
}

// ============================================================================
// SymbolCollection management (private)
// ============================================================================

@(private = "package")
make_symbol_collection :: proc(config: ^common.Config) -> SymbolCollection {
	return SymbolCollection {
		config = config,
		packages = make(map[string]SymbolPackage, 16),
		unique_strings = make(map[string]string, 16),
	}
}

@(private = "package")
delete_symbol_collection :: proc(collection: SymbolCollection) {
	// No-op: temp allocator cleanup is automatic at request end
}

@(private = "package")
get_or_create_package :: proc(collection: ^SymbolCollection, pkg_name: string) -> ^SymbolPackage {
	pkg := &collection.packages[pkg_name]
	if pkg == nil || pkg.symbols == nil {
		collection.packages[pkg_name] = {}
		pkg = &collection.packages[pkg_name]
		pkg.symbols = make(map[string]Symbol, 100)
		pkg.methods = make(map[Method][dynamic]Symbol, 100)
		pkg.objc_structs = make(map[string]ObjcStruct, 5)
		pkg.proc_group_members = make(map[string]bool, 10)
		pkg.file_sources = make(map[string]FileSource, 10)
	}
	return pkg
}

// ============================================================================
// Public Cache Accessors
// ============================================================================

// Lookup a symbol by name and package from the global cache.
// Returns a copy of the symbol.
lookup_symbol :: proc(name: string, pkg: string) -> (Symbol, bool) {
	if name == "" {
		return {}, false
	}

	if _pkg, ok := &g_symbol_cache.packages[pkg]; ok {
		if symbol, ok := _pkg.symbols[name]; ok {
			return symbol, true
		}
	}
	return {}, false
}

// Get all symbol names in a package.
// Returns a copy of symbol names, allocated with the provided allocator.
get_package_symbol_names :: proc(pkg: string, allocator := context.allocator) -> []string {
	if _pkg, ok := g_symbol_cache.packages[pkg]; ok {
		result := make([dynamic]string, 0, len(_pkg.symbols), allocator)
		for name in _pkg.symbols {
			append(&result, strings.clone(name, allocator))
		}
		return result[:]
	}
	return {}
}

// Get all symbols in a package.
// Returns a copy of symbols, allocated with the provided allocator.
get_package_symbols :: proc(pkg: string, allocator := context.allocator) -> []Symbol {
	if _pkg, ok := g_symbol_cache.packages[pkg]; ok {
		result := make([dynamic]Symbol, 0, len(_pkg.symbols), allocator)
		for _, symbol in _pkg.symbols {
			append(&result, symbol)
		}
		return result[:]
	}
	return {}
}

// Get all package names from the cache.
// Returns a copy, allocated with the provided allocator.
get_all_package_names :: proc(allocator := context.allocator) -> []string {
	result := make([dynamic]string, 0, len(g_symbol_cache.packages), allocator)
	for name in g_symbol_cache.packages {
		append(&result, strings.clone(name, allocator))
	}
	return result[:]
}

// Get methods for a given method key from a package.
// Returns a copy of the method symbols, allocated with the provided allocator.
get_methods :: proc(pkg: string, method: Method, allocator := context.allocator) -> []Symbol {
	if _pkg, ok := &g_symbol_cache.packages[pkg]; ok {
		if symbols, ok := _pkg.methods[method]; ok {
			result := make([]Symbol, len(symbols), allocator)
			for symbol, i in symbols {
				result[i] = symbol
			}
			return result
		}
	}
	return {}
}

// Get all methods across all packages for a given method key.
// Returns a copy of the method symbols, allocated with the provided allocator.
get_all_methods :: proc(method: Method, allocator := context.allocator) -> []Symbol {
	result := make([dynamic]Symbol, 0, allocator)
	for _, &_pkg in g_symbol_cache.packages {
		if symbols, ok := _pkg.methods[method]; ok {
			for symbol in symbols {
				append(&result, symbol)
			}
		}
	}
	return result[:]
}

// Check if a package exists in the cache.
has_package :: proc(pkg: string) -> bool {
	return pkg in g_symbol_cache.packages
}

// Get an objc struct by name from a package.
// Returns a copy of the struct.
get_objc_struct :: proc(pkg: string, name: string) -> (ObjcStruct, bool) {
	if _pkg, ok := g_symbol_cache.packages[pkg]; ok {
		if objc, ok := _pkg.objc_structs[name]; ok {
			return objc, true
		}
	}
	return {}, false
}

// Check if a procedure name is part of a proc group in a package.
is_proc_group_member :: proc(pkg: string, proc_name: string) -> bool {
	if _pkg, ok := g_symbol_cache.packages[pkg]; ok {
		return proc_name in _pkg.proc_group_members
	}
	return false
}

// Get imports for a package.
// Returns a copy, allocated with the provided allocator.
get_package_imports :: proc(pkg: string, allocator := context.allocator) -> []string {
	if _pkg, ok := g_symbol_cache.packages[pkg]; ok {
		result := make([]string, len(_pkg.imports), allocator)
		for imp, i in _pkg.imports {
			result[i] = strings.clone(imp, allocator)
		}
		return result
	}
	return {}
}

// Get all file sources across all packages
// Returns an iterator-friendly slice of file sources
get_all_file_sources :: proc(allocator := context.allocator) -> []FileSource {
	result := make([dynamic]FileSource, 0, allocator)
	for _, pkg in g_symbol_cache.packages {
		for _, source in pkg.file_sources {
			append(&result, source)
		}
	}
	return result[:]
}

// Collect symbols from a parsed file into the global cache.
// This is used by tests and the document update path.
collect_symbols_to_cache :: proc(file: ast.File, uri: string) -> common.Error {
	return collect_symbols(&g_symbol_cache, file, uri)
}