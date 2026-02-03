package main

import "src:diagnostics"
import "src:analysis"
import "base:intrinsics"

import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:thread"

import "src:common"
import "src:server"

VERSION := #config(VERSION, "dev")

Tcp_Context :: struct {
	socket: net.TCP_Socket,
}

tcp_read :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ctx := cast(^Tcp_Context)handle
	bytes_read, err := net.recv_tcp(ctx.socket, data)
	if err != nil {
		return 0, 1
	}
	return bytes_read, 0
}

tcp_write :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ctx := cast(^Tcp_Context)handle
	bytes_written, err := net.send_tcp(ctx.socket, data)
	if err != nil {
		return 0, 1
	}
	return bytes_written, 0
}

os_read :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr := cast(^os.Handle)handle
	a, b := os.read(ptr^, data)
	return a, cast(int)(b != nil)
}

os_write :: proc(handle: rawptr, data: []byte) -> (int, int) {
	ptr := cast(^os.Handle)handle
	a, b := os.write(ptr^, data)
	return a, cast(int)(b != nil)
}

//Note(Daniel, Should look into handling errors without crashing from parsing)

request_thread: ^thread.Thread

run :: proc(reader: ^server.Reader, writer: ^server.Writer) {
	log.info("Initializing Configs")
	common.config_storage_init()
	defer common.config_storage_shutdown()
	log.info("Initializing Document Storage")
	server.document_storage_init()
	defer server.document_storage_shutdown()
	log.info("Initializing Analysis")
	analysis.init_symbol_cache(&common.config)
	defer analysis.shutdown_symbol_cache()
	log.info("Initializing Diagnostics")
	diagnostics.init()
	defer diagnostics.shutdown()

	common.config.running = true

	request_thread_data := server.RequestThreadData {
		reader = reader,
		writer = writer,
	}


	server.requests = make([dynamic]server.Request, context.allocator)
	server.deletings = make([dynamic]server.Request, context.allocator)
	defer delete(server.requests)
	defer delete(server.deletings)

	request_thread = thread.create_and_start_with_data(cast(rawptr)&request_thread_data, server.thread_request_main)

	log.info("Starting Odin Language Server", VERSION)

	for common.config.running {
		server.consume_requests(&common.config, writer)
	}
}

end :: proc() {
}

parse_args :: proc() -> (use_tcp: bool, port: int, ok: bool) {
	use_tcp = false
	port = 0
	ok = true

	for arg in os.args[1:] {
		switch {
		case arg == "version":
			fmt.println("ols version", VERSION)
			os.exit(0)
		case arg == "--stdio":
			use_tcp = false
		case arg == "--tcp":
			use_tcp = true
		case strings.has_prefix(arg, "--port="):
			port_str := strings.trim_prefix(arg, "--port=")
			parsed_port, parse_ok := strconv.parse_int(port_str)
			if !parse_ok || parsed_port <= 0 || parsed_port > 65535 {
				fmt.eprintln("Invalid port number:", port_str)
				ok = false
				return
			}
			port = parsed_port
		case:
			fmt.eprintln("Unknown argument:", arg)
			ok = false
			return
		}
	}

	if use_tcp && port == 0 {
		fmt.eprintln("TCP mode requires --port=<number> argument")
		ok = false
		return
	}

	return
}

run_stdio :: proc() {
	reader := server.make_reader(os_read, cast(rawptr)&os.stdin)
	writer := server.make_writer(os_write, cast(rawptr)&os.stdout)
	run(&reader, &writer)
}

run_tcp :: proc(port: int) {
	endpoint := net.Endpoint {
		address = net.IP4_Loopback,
		port    = port,
	}

	listen_socket, listen_err := net.listen_tcp(endpoint)
	if listen_err != nil {
		fmt.eprintln("Failed to listen on port", port, ":", listen_err)
		os.exit(1)
	}
	defer net.close(listen_socket)

	fmt.println("OLS listening on 127.0.0.1:", port)

	client_socket, _, accept_err := net.accept_tcp(listen_socket)
	if accept_err != nil {
		fmt.eprintln("Failed to accept connection:", accept_err)
		os.exit(1)
	}
	defer net.close(client_socket)

	fmt.println("Client connected")

	tcp_ctx := Tcp_Context {
		socket = client_socket,
	}

	reader := server.make_reader(tcp_read, cast(rawptr)&tcp_ctx)
	writer := server.make_writer(tcp_write, cast(rawptr)&tcp_ctx)

	run(&reader, &writer)
}

main :: proc() {
	use_tcp, port, args_ok := parse_args()
	if !args_ok {
		os.exit(1)
	}

	init_global_temporary_allocator(mem.Megabyte * 100)

	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)
	}

	logger := server.init_file_logger(common.config.verbose)
	defer server.shutdown_file_logger()
	context.logger = logger

	if use_tcp {
		run_tcp(port)
	} else {
		run_stdio()
	}

	when ODIN_DEBUG {
		for key, value in tracking_allocator.allocation_map {
			log.errorf("%v: Leaked %v bytes\n", value.location, value.size)
		}
	}
}
