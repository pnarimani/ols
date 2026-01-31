package server

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:sync"

File_Logger_Data :: struct {
	file_handle: os.Handle,
	mutex:       sync.Mutex,
}

@(private = "file")
g_logger_data: File_Logger_Data

init_file_logger :: proc(verbose: bool) -> log.Logger {
	exe_path := os.args[0]
	exe_dir := filepath.dir(exe_path, context.temp_allocator)
	log_path := filepath.join({exe_dir, "ols.log"}, context.temp_allocator)

	file_handle, err := os.open(log_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	if err != nil {
		fmt.eprintln("Failed to open log file:", log_path)
		file_handle = os.INVALID_HANDLE
	}

	g_logger_data.file_handle = file_handle

	lowest := log.Level.Error
	when ODIN_DEBUG {
		lowest = log.Level.Debug
	} else {
		if verbose {
			lowest = log.Level.Debug
		}
	}

	return log.Logger{file_logger_proc, &g_logger_data, lowest, {}}
}

shutdown_file_logger :: proc() {
	if g_logger_data.file_handle != os.INVALID_HANDLE {
		os.close(g_logger_data.file_handle)
	}
}

@(private = "file")
file_logger_proc :: proc(
	logger_data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	data := cast(^File_Logger_Data)logger_data
	if data == nil || data.file_handle == os.INVALID_HANDLE {
		return
	}

	sync.lock(&data.mutex)
	defer sync.unlock(&data.mutex)

	thread_id := os.current_thread_id()

	level_str: string
	switch level {
	case .Debug:
		level_str = "DEBUG"
	case .Info:
		level_str = "INFO"
	case .Warning:
		level_str = "WARN"
	case .Error:
		level_str = "ERROR"
	case .Fatal:
		level_str = "FATAL"
	}

	message := fmt.tprintf("[%d] [%s] %s\n", thread_id, level_str, text)
	os.write_string(data.file_handle, message)
}
