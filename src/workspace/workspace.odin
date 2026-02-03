package workspace

import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import "src:common"

FileInfo :: struct {
	fullpath: string,
	text:     string,
}

@(private)
MockFile :: struct {
	fullpath: string,
	text:     string,
}

@(private)
mock_files: [dynamic]MockFile

register_mock_file :: proc(fullpath: string, text: string) {
	if !ODIN_TEST {
		panic("register_mock_file can only be used in test mode")
	}
	append(&mock_files, MockFile{fullpath = fullpath, text = text})
}

clear_mock_files :: proc() {
	if !ODIN_TEST {
		panic("clear_mock_files can only be used in test mode")
	}
	free(&mock_files)
	mock_files = nil
}

get_files :: proc(allocator := context.allocator) -> []FileInfo {
	when ODIN_TEST {
		return iterate_mock_files(allocator)
	} else {
		return iterate_real_files(&common.config, allocator)
	}
}

read_file_content :: proc(fullpath: string, allocator := context.allocator) -> (string, bool) {
	when ODIN_TEST {


		for mock_file in mock_files {
			if mock_file.fullpath == fullpath {
				return strings.clone(mock_file.text, allocator), true
			}
		}

		if strings.contains(fullpath, "builtin") ||
		   strings.contains(fullpath, "base/runtime") ||
		   strings.contains(fullpath, "core") {
			data, ok := os.read_entire_file(fullpath, allocator)
			if ok {
				return string(data), true
			}
		}

		sb := strings.Builder{}
		strings.builder_init(&sb, allocator)
		strings.write_string(&sb, "Mock file not found: ")
		strings.write_string(&sb, fullpath)
		panic(strings.to_string(sb))
	} else {
		data, ok := os.read_entire_file(fullpath, allocator)
		if !ok {
			return "", false
		}
		return string(data), true
	}
}

@(private)
iterate_mock_files :: proc(allocator := context.allocator) -> []FileInfo {
	result := make([dynamic]FileInfo, allocator)
	for mock_file in mock_files {
		info := FileInfo {
			fullpath = mock_file.fullpath,
			text     = mock_file.text,
		}

		append(&result, info)
	}

	return result[:]
}

@(private)
iterate_real_files :: #force_inline proc(config: ^common.Config, allocator := context.allocator) -> []FileInfo {
	WalkDirectoriesData :: struct {
		fullpaths: ^[dynamic]string,
	}

	walk_directories :: proc(
		info: os.File_Info,
		in_err: os.Errno,
		user_data: rawptr,
	) -> (
		err: os.Error,
		skip_dir: bool,
	) {
		data := cast(^WalkDirectoriesData)user_data

		if info.is_dir {
			return nil, false
		}

		if info.fullpath == "" {
			return nil, false
		}

		if strings.contains(info.name, ".odin") {
			slash_path, _ := filepath.to_slash(info.fullpath, context.temp_allocator)
			append(data.fullpaths, strings.clone(info.fullpath))
		}

		return nil, false
	}
	results := make([dynamic]FileInfo, allocator)
	fullpaths := make([dynamic]string, context.temp_allocator)

	walk_data := WalkDirectoriesData {
		fullpaths = &fullpaths,
	}
	for workspace in common.config.workspace_folders {
		path, _ := common.uri_to_path(workspace.uri, context.temp_allocator)
		filepath.walk(path, walk_directories, &walk_data)
	}

	unique_fullpaths := slice.unique(fullpaths[:])

	for fullpath in unique_fullpaths {
		data, ok := os.read_entire_file(fullpath, allocator)

		if !ok {
			log.errorf("failed to read entire file for indexing %v", fullpath)
			continue
		}

		info := FileInfo {
			fullpath = fullpath,
			text     = string(data),
		}

		append(&results, info)
	}

	return results[:]

}
