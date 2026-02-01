#+feature dynamic-literals
package server

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:strings"

import "src:common"

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

// Build symbols from a package into the provided symbol collection.
// No caching - symbols are built fresh each time.
build_package_symbols :: proc(symbols: ^SymbolCollection, pkg_name: string, loaded_pkgs: ^map[string]bool) {
	// Check if already loaded in this request to avoid infinite loops
	if pkg_name in loaded_pkgs {
		return
	}
	loaded_pkgs[pkg_name] = true

	matches, err := filepath.glob(fmt.tprintf("%v/*.odin", pkg_name), context.temp_allocator)

	if err != .None {
		log.errorf("Failed to glob %v for indexing package", pkg_name)
		return
	}

	for fullpath in matches {
		if skip_file(filepath.base(fullpath)) {
			continue
		}

		data, ok := os.read_entire_file(fullpath, context.temp_allocator)

		if !ok {
			log.errorf("failed to read entire file for indexing %v", fullpath)
			continue
		}

		p := parser.Parser {
			err   = log_error_handler,
			warn  = log_warning_handler,
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
			src      = string(data),
			pkg      = pkg,
		}

		ok = parser.parse_file(&p, &file)

		if !ok {
			if !strings.contains(fullpath, "builtin.odin") && !strings.contains(fullpath, "intrinsics.odin") {
				log.errorf("error in parse file for indexing %v", fullpath)
			}
			continue
		}

		uri := common.create_uri(fullpath, context.temp_allocator)

		collect_symbols(symbols, file, uri.uri)
	}
}

// Get the builtin package path
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

// Build a fresh symbol collection for a request.
// Includes builtins, runtime, and the specified imports.
build_request_symbols :: proc(imports: []Package, config: ^common.Config = nil) -> SymbolCollection {
	// Use provided config or fall back to global config
	actual_config := config if config != nil else &common.config
	symbols := make_symbol_collection(actual_config)
	loaded_pkgs := make(map[string]bool, 16)

	// Always load builtins
	builtin_path := get_builtin_path()
	if os.exists(builtin_path) {
		build_package_symbols(&symbols, builtin_path, &loaded_pkgs)
	}

	// Load runtime
	runtime_path := get_runtime_path()
	if runtime_path != "" && os.exists(runtime_path) {
		build_package_symbols(&symbols, runtime_path, &loaded_pkgs)
	}

	// Load all imported packages
	for imp in imports {
		build_package_symbols(&symbols, imp.name, &loaded_pkgs)
	}

	return symbols
}

log_error_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	log.warnf("%v %v %v", pos, msg, args)
}

log_warning_handler :: proc(pos: tokenizer.Pos, msg: string, args: ..any) {
	log.warnf("%v %v %v", pos, msg, args)
}
