package server

import "src:analysis"
import "src:common"

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

//Used in semantic tokens and inlay hints to handle the entire file being resolved.

FileResolve :: struct {
	symbols: map[uintptr]analysis.SymbolAndNode,
}

// Find all package aliases from all collections.
// Returns a map from collection name -> list of package paths.
// Allocates in the provided allocator.
find_all_package_aliases :: proc(allocator := context.temp_allocator) -> map[string][dynamic]string {
	result := make(map[string][dynamic]string, allocator = allocator)

	walk_proc :: proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Errno, skip_dir: bool) {
		data := cast(^[dynamic]string)user_data

		if !info.is_dir && filepath.ext(info.name) == ".odin" {
			dir := filepath.dir(info.fullpath, context.temp_allocator)
			if !slice.contains(data[:], dir) {
				append(data, dir)
			}
		}

		return in_err, false
	}

	for k, v in common.config.collections {
		pkgs := make([dynamic]string, context.temp_allocator)
		filepath.walk(v, walk_proc, &pkgs)

		for pkg in pkgs {
			if pkg, err := filepath.rel(v, pkg, context.temp_allocator); err == .None {
				forward_pkg, _ := filepath.to_slash(pkg, context.temp_allocator)
				if k not_in result {
					result[k] = make([dynamic]string, allocator)
				}

				aliases := &result[k]

				append(aliases, strings.clone(forward_pkg, allocator))
			}
		}
	}

	return result
}
