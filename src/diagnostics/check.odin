package diagnostics

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strings"

import "src:common"

Json_Error :: struct {
	type: string,
	pos:  Json_Type_Error,
	msgs: []string,
}

Json_Type_Error :: struct {
	file:       string,
	offset:     int,
	line:       int,
	column:     int,
	end_column: int,
}

Json_Errors :: struct {
	error_count: int,
	errors:      []Json_Error,
}

// If the user does not specify where to call odin check, it'll just find all directory with odin, and call them seperately.
fallback_find_odin_directories :: proc(config: ^common.Config) -> []string {
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

	data := make([dynamic]string, context.temp_allocator)

	if len(config.workspace_folders) > 0 {
		if uri, ok := common.parse_uri(config.workspace_folders[0].uri, context.temp_allocator); ok {
			filepath.walk(uri.path, walk_proc, &data)
		}
	}

	return data[:]
}

check :: proc(paths: []string, uri: common.Uri, config: ^common.Config) {
	paths := paths

	if len(paths) == 0 {
		if config.enable_checker_only_saved {
			paths = {path.dir(uri.path, context.temp_allocator)}
		} else {
			paths = fallback_find_odin_directories(config)
		}
	}

	// Clear .Check diagnostics for all URIs that previously had them
	// (we're about to re-check and will add back any that still exist)
	previous_check_uris := get_uris_with_diagnostic_type(.Check, context.temp_allocator)
	for prev_uri in previous_check_uris {
		begin_diagnostic_update(prev_uri, .Check)
	}

	// Track which URIs we add diagnostics to (for those not in previous list)
	checked_uris := make(map[string]bool, 32, context.temp_allocator)

	data := make([]byte, mem.Kilobyte * 200, context.temp_allocator)

	buffer: []byte
	code: u32
	ok: bool

	collection_builder := strings.builder_make(context.temp_allocator)

	for k, v in common.config.collections {
		if k == "" || k == "core" || k == "vendor" || k == "base" {
			continue
		}
		strings.write_string(&collection_builder, fmt.aprintf("-collection:%v=\"%v\" ", k, v))
	}

	for check_path in paths {
		command: string

		if config.odin_command != "" {
			command = config.odin_command
		} else {
			command = "odin"
		}

		entry_point_opt := filepath.ext(check_path) == ".odin" ? "-file" : "-no-entry-point"

		slice.zero(data)

		if code, ok, buffer = common.run_executable(
			fmt.tprintf(
				"%v check \"%s\" %s %s %s %s %s",
				command,
				check_path,
				strings.to_string(collection_builder),
				entry_point_opt,
				config.checker_args,
				"-json-errors",
				ODIN_OS == .Linux || ODIN_OS == .Darwin ? "2>&1" : "",
			),
			&data,
		); !ok {
			log.errorf("Odin check failed with code %v for file %v", code, check_path)
			return
		}

		if len(buffer) == 0 {
			continue
		}

		json_errors: Json_Errors

		if res := json.unmarshal(buffer, &json_errors, json.DEFAULT_SPECIFICATION, context.temp_allocator);
		   res != nil {
			log.errorf("Failed to unmarshal check results: %v, %v", res, string(buffer))
		}

		for error in json_errors.errors {
			if len(error.msgs) == 0 {
				break
			}

			message := strings.join(error.msgs, "\n", context.temp_allocator)

			if strings.contains(message, "Redeclaration of 'main' in this scope") {
				continue
			}

			error_path := error.pos.file

			when ODIN_OS == .Windows {
				error_path = common.get_case_sensitive_path(error_path, context.temp_allocator)
			}

			error_uri := common.create_uri(error_path, context.temp_allocator)

			// If this URI wasn't in the previous list and we haven't seen it yet,
			// begin an update for it (to ensure clean slate)
			if error_uri.uri not_in checked_uris {
				checked_uris[error_uri.uri] = true
				// Only call begin_diagnostic_update if not already cleared above
				has_previous := false
				for prev_uri in previous_check_uris {
					if prev_uri == error_uri.uri {
						has_previous = true
						break
					}
				}
				if !has_previous {
					begin_diagnostic_update(error_uri.uri, .Check)
				}
			}

			add_diagnostic(
				.Check,
				error_uri.uri,
				Diagnostic {
					code = "checker",
					severity = .Error,
					range = {
						// odin will sometimes report errors on column 0, so we ensure we don't provide a negative column/line to the client
						start = {character = max(error.pos.column - 1, 0), line = max(error.pos.line - 1, 0)},
						end = {character = max(error.pos.end_column - 1, 0), line = max(error.pos.line - 1, 0)},
					},
					message = message,
				},
			)
		}
	}
}
