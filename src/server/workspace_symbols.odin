package server

import "src:analysis"

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "src:common"

dir_blacklist :: []string{"node_modules", ".git"}

@(private)
walk_dir :: proc(info: os.File_Info, in_err: os.Errno, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
	pkgs := cast(^[dynamic]string)user_data

	if info.is_dir {
		dir, _ := filepath.to_slash(info.fullpath, context.temp_allocator)
		dir_name := filepath.base(dir)

		for blacklist in dir_blacklist {
			if blacklist == dir_name {
				return nil, true
			}
		}
		append(pkgs, dir)
	}

	return nil, false
}

// Find all packages in the workspace (computes fresh every time)
find_workspace_packages :: proc(allocator := context.temp_allocator) -> []string {
	workspace_pkgs := make([dynamic]string, 0, allocator)

	for workspace in common.config.workspace_folders {
		path := common.uri_to_path(workspace.uri, context.temp_allocator) or_continue
		pkgs := make([dynamic]string, 0, context.temp_allocator)

		filepath.walk(path, walk_dir, &pkgs)

		_pkg: for pkg in pkgs {
			matches, err := filepath.glob(fmt.tprintf("%v/*.odin", pkg), context.temp_allocator)

			if len(matches) == 0 {
				continue
			}

			for exclude_path in common.config.profile.exclude_path {
				exclude_forward, _ := filepath.to_slash(exclude_path, context.temp_allocator)

				if exclude_forward[len(exclude_forward) - 2:] == "**" {
					lower_pkg := strings.to_lower(pkg)
					lower_exclude := strings.to_lower(exclude_forward[:len(exclude_forward) - 3])
					if strings.contains(lower_pkg, lower_exclude) {
						continue _pkg
					}
				} else {
					lower_pkg := strings.to_lower(pkg)
					lower_exclude := strings.to_lower(exclude_forward)
					if lower_pkg == lower_exclude {
						continue _pkg
					}
				}
			}

			append(&workspace_pkgs, strings.clone(pkg, allocator))
		}
	}

	return workspace_pkgs[:]
}

get_workspace_symbols :: proc(query: string) -> (workspace_symbols: []WorkspaceSymbol, ok: bool) {
	// Find all workspace packages
	workspace_pkgs := find_workspace_packages()

	for pkg in workspace_pkgs {
		analysis.load_package(pkg)
	}

	limit :: 100
	result_symbols := make([dynamic]WorkspaceSymbol, 0, limit, context.temp_allocator)
	if results, ok := fuzzy_search(query, workspace_pkgs[:], "", resolve_fields = false, limit = limit); ok {
		for result in results {
			symbol := WorkspaceSymbol {
				name = result.symbol.name,
				location = {range = result.symbol.range, uri = common.path_to_uri(result.symbol.filepath, context.temp_allocator)},
				kind = symbol_kind_to_type(result.symbol.type),
			}

			append(&result_symbols, symbol)
		}
	}

	return result_symbols[:], true
}
