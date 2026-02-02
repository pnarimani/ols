package analysis

import "core:strings"

import "src:common"

// ============================================================================
// String interning
// ============================================================================

get_index_unique_string :: proc {
	get_index_unique_string_collection,
	get_index_unique_string_collection_raw,
}

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
// SymbolCollection management
// ============================================================================

make_symbol_collection :: proc(config: ^common.Config) -> SymbolCollection {
	return SymbolCollection {
		config = config,
		packages = make(map[string]SymbolPackage, 16),
		unique_strings = make(map[string]string, 16),
	}
}

delete_symbol_collection :: proc(collection: SymbolCollection) {
	// No-op: temp allocator cleanup is automatic at request end
}

get_or_create_package :: proc(collection: ^SymbolCollection, pkg_name: string) -> ^SymbolPackage {
	pkg := &collection.packages[pkg_name]
	if pkg == nil || pkg.symbols == nil {
		collection.packages[pkg_name] = {}
		pkg = &collection.packages[pkg_name]
		pkg.symbols = make(map[string]Symbol, 100)
		pkg.methods = make(map[Method][dynamic]Symbol, 100)
		pkg.objc_structs = make(map[string]ObjcStruct, 5)
		pkg.proc_group_members = make(map[string]bool, 10)
	}
	return pkg
}
