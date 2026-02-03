#+feature dynamic-literals
package analysis

import "src:urilib"
import "core:os"
import "src:workspace"
import "base:runtime"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strings"

import "src:common"
import doc "src:documents"

@(private = "package")
g_symbol_cache: SymbolCollection

// Initialize the global symbol cache. Called once at startup.
init_symbol_cache :: proc(config: ^common.Config) {
	g_symbol_cache = SymbolCollection {
		allocator      = context.allocator,
		config         = config,
		packages       = make(map[string]SymbolPackage, 64),
	}

	strings.intern_init(&g_symbol_cache.intern)

	// Load builtins at startup
	builtin_path := get_builtin_path()
	if os.exists(builtin_path) {
		load_package(builtin_path)
	}

	// Load runtime at startup
	runtime_path := get_runtime_path()
	if runtime_path != "" && os.exists(runtime_path) {
		load_package(runtime_path)
	}
}

// Reset the symbol cache (for testing purposes).
shutdown_symbol_cache :: proc() {
	// Clear package data
	for _, &pkg in g_symbol_cache.packages {
		delete(pkg.symbols)
		delete(pkg.objc_structs)
		delete(pkg.methods)
		delete(pkg.imports)
		delete(pkg.proc_group_members)
	}
	clear(&g_symbol_cache.packages)
	strings.intern_destroy(&g_symbol_cache.intern)
}

// Update the cache for a specific document.
// This parses the document and collects its symbols into the global cache,
// replacing any existing symbols from that file.
update_doc :: proc(file: ast.File) {
	context.allocator = g_symbol_cache.allocator
	collect_symbols(&g_symbol_cache, file)
}

// ============================================================================
// Platform configuration
// ============================================================================

@(private)
platform_os: map[string]struct{} = {
	"windows" = {},
	"linux"   = {},
	"essence" = {},
	"js"      = {},
	"freebsd" = {},
	"darwin"  = {},
	"wasm32"  = {},
	"openbsd" = {},
	"wasi"    = {},
	"wasm"    = {},
	"haiku"   = {},
	"netbsd"  = {},
	"freebsd" = {},
}


os_enum_to_string: [runtime.Odin_OS_Type]string = {
	.Windows      = "windows",
	.Darwin       = "darwin",
	.Linux        = "linux",
	.Essence      = "essence",
	.FreeBSD      = "freebsd",
	.WASI         = "wasi",
	.JS           = "js",
	.Freestanding = "freestanding",
	.Haiku        = "haiku",
	.OpenBSD      = "openbsd",
	.NetBSD       = "netbsd",
	.Orca         = "orca",
	.Unknown      = "unknown",
}

@(private)
os_string_to_enum: map[string]runtime.Odin_OS_Type = {
	"Windows"      = .Windows,
	"windows"      = .Windows,
	"Darwin"       = .Darwin,
	"darwin"       = .Darwin,
	"Linux"        = .Linux,
	"linux"        = .Linux,
	"Essence"      = .Essence,
	"essence"      = .Essence,
	"Freebsd"      = .FreeBSD,
	"freebsd"      = .FreeBSD,
	"FreeBSD"      = .FreeBSD,
	"Wasi"         = .WASI,
	"wasi"         = .WASI,
	"WASI"         = .WASI,
	"Js"           = .JS,
	"js"           = .JS,
	"JS"           = .JS,
	"Freestanding" = .Freestanding,
	"freestanding" = .Freestanding,
	"Wasm"         = .JS,
	"wasm"         = .JS,
	"Haiku"        = .Haiku,
	"haiku"        = .Haiku,
	"Openbsd"      = .OpenBSD,
	"openbsd"      = .OpenBSD,
	"OpenBSD"      = .OpenBSD,
	"Netbsd"       = .NetBSD,
	"netbsd"       = .NetBSD,
	"NetBSD"       = .NetBSD,
	"Orca"         = .Orca,
	"orca"         = .Orca,
	"Unknown"      = .Unknown,
	"unknown"      = .Unknown,
}

@(private = "file")
is_bsd_variant :: proc(name: string) -> bool {
	return(
		common.config.profile.os == os_enum_to_string[.FreeBSD] ||
		common.config.profile.os == os_enum_to_string[.OpenBSD] ||
		common.config.profile.os == os_enum_to_string[.NetBSD] \
	)
}

@(private = "file")
is_unix_variant :: proc(name: string) -> bool {
	return(
		common.config.profile.os == os_enum_to_string[.Linux] ||
		common.config.profile.os == os_enum_to_string[.Darwin] \
	)
}

skip_file :: proc(filename: string) -> bool {
	last_underscore_index := strings.last_index(filename, "_")
	last_dot_index := strings.last_index(filename, ".")

	if last_underscore_index + 1 < last_dot_index {
		name_between := filename[last_underscore_index + 1:last_dot_index]

		if name_between == "unix" {
			return !is_unix_variant(name_between)
		}

		if name_between == "bsd" {
			return !is_bsd_variant(name_between)
		}

		if _, ok := platform_os[name_between]; ok {
			return name_between != common.config.profile.os
		}
	}

	return false
}

should_collect_file :: proc(file_tags: parser.File_Tags) -> bool {
	if file_tags.ignore {
		return false
	}

	if len(file_tags.build) > 0 {
		when_expr_map := make(map[string]When_Expr, context.temp_allocator)

		for key, value in common.config.profile.defines {
			when_expr_map[key] = resolve_when_ident(when_expr_map, value) or_continue
		}

		if when_expr, ok := resolve_when_ident(when_expr_map, "ODIN_OS"); ok {
			if s, ok := when_expr.(string); ok {
				if used_os, ok := os_string_to_enum[when_expr.(string)]; ok {
					found := false
					for tag in file_tags.build {
						if used_os in tag.os {
							found = true
							break
						}
					}
					if !found {
						return false
					}
				}
			}
		}
	}
	return true
}

load_package :: proc(pkg_name: string) {
	context.allocator = g_symbol_cache.allocator
	if pkg_name == "" || !os.exists(pkg_name) {
		return
	}

	if pkg_name in g_symbol_cache.packages {
		return
	}

	matches, err := filepath.glob(fmt.tprintf("%v/*.odin", pkg_name), context.temp_allocator)

	if err != .None {
		log.errorf("Failed to glob %v for indexing package", pkg_name)
		return
	}

	for fullpath in matches {
		if skip_file(filepath.base(fullpath)) {
			continue
		}

		data, ok := workspace.read_file_content(fullpath, context.temp_allocator)

		if !ok {
			log.errorf("failed to read entire file for indexing %v", fullpath)
			continue
		}

		analyze_file(fullpath, string(data))
	}
}

analyze_file :: proc(fullpath, text: string) {
	assert(urilib.is_file_uri(fullpath) == false, "Expected filesystem path, got URI")

	p := parser.Parser {
		flags = {.Optional_Semicolons},
	}

	dir := filepath.base(filepath.dir(fullpath, context.temp_allocator))

	pkg := new(ast.Package, context.temp_allocator)
	pkg.kind = .Normal
	pkg.fullpath = fullpath
	pkg.name = dir

	if dir == "runtime" {
		pkg.kind = .Runtime
	}

	file := ast.File {
		fullpath = fullpath,
		src      = text,
		pkg      = pkg,
	}

	ok := parser.parse_file(&p, &file)

	if !ok {
			log.errorf("error in parse file for indexing %v", fullpath)
		return
	}

	collect_symbols(&g_symbol_cache, file)
}

// Get the builtin package path
@(private = "package")
get_builtin_path :: proc() -> string {
	dir_exe := common.get_executable_path(context.temp_allocator)
	return path.join({dir_exe, "builtin"}, context.temp_allocator)
}

// Get the runtime package path
get_runtime_path :: proc() -> string {
	if base, ok := common.config.collections["base"]; ok {
		return path.join({base, "runtime"}, context.temp_allocator)
	}
	return ""
}