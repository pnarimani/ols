#+feature dynamic-literals
package server

import "base:intrinsics"
import "base:runtime"
import doc "src:documents"

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import path "core:path/slashpath"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "src:analysis"
import "src:common"
import "src:documents"

Header :: struct {
	content_length: int,
	content_type:   string,
}

RequestInfo :: struct {
	root:     json.Value,
	params:   json.Value,
	document: ^documents.DocumentData,
	id:       RequestId,
	config:   ^common.Config,
	writer:   ^Writer,
	result:   common.Error,
}

make_response_message :: proc(id: RequestId, params: ResponseParams) -> ResponseMessage {
	return ResponseMessage{jsonrpc = "2.0", id = id, result = params}
}

make_response_message_error :: proc(id: RequestId, error: ResponseError) -> ResponseMessageError {
	return ResponseMessageError{jsonrpc = "2.0", id = id, error = error}
}

RequestThreadData :: struct {
	reader: ^Reader,
	writer: ^Writer,
}

Request :: struct {
	allocator:       mem.Allocator,
	id:              RequestId,
	value:           json.Value,
	is_notification: bool,
}


requests_sempahore: sync.Sema
requests_mutex: sync.Mutex

requests: [dynamic]Request
deletings: [dynamic]Request

thread_request_main :: proc(data: rawptr) {
	request_data := cast(^RequestThreadData)data
	context.logger = get_file_logger()

	for common.config.running {
		defer free_all(context.temp_allocator)

		header, success := read_and_parse_header(request_data.reader)

		if (!success) {
			log.error("Failed to read and parse header")
			return
		}

		value: json.Value
		value, success = read_and_parse_body(request_data.reader, header)

		if (!success) {
			log.error("Failed to read and parse body")
			return
		}

		root, ok := value.(json.Object)

		if !ok {
			log.error("No root object")
			return
		}

		id: RequestId
		id_value: json.Value
		id_value, ok = root["id"]

		if ok {
			#partial switch v in id_value {
			case json.String:
				id = v
				//Hack to support dynamic registering without changing too much
				if v == "REGISTER_DYNAMIC_CAPABILITIES" {
					json.destroy_value(root)
					continue
				}
			case json.Integer:
				id = v
			case:
				id = 0
			}
		}

		sync.mutex_lock(&requests_mutex)

		method := root["method"].(json.String)

		if method == "$/cancelRequest" {
			append(&deletings, Request{id = id, value = root, allocator = context.allocator})
		} else if method in notification_map {
			append(&requests, Request{value = root, is_notification = true, allocator = context.allocator})
			sync.sema_post(&requests_sempahore)
		} else {
			append(&requests, Request{id = id, value = root, allocator = context.allocator})
			sync.sema_post(&requests_sempahore)
		}

		sync.mutex_unlock(&requests_mutex)
	}
}

read_and_parse_header :: proc(reader: ^Reader) -> (Header, bool) {
	header: Header

	builder := strings.builder_make(context.temp_allocator)

	found_content_length := false

	for true {
		strings.builder_reset(&builder)

		if !read_until_delimiter(reader, '\n', &builder) {
			log.error("Failed to read with delimiter")
			return header, false
		}

		message := strings.to_string(builder)

		if len(message) < 2 || message[len(message) - 2] != '\r' {
			log.error("No carriage return")
			return header, false
		}

		if len(message) == 2 {
			break
		}

		index := strings.last_index_byte(message, ':')

		if index == -1 {
			log.error("Failed to find semicolon")
			return header, false
		}

		header_name := message[0:index]
		header_value := message[len(header_name) + 2:len(message) - 2]

		if strings.compare(header_name, "Content-Length") == 0 {
			if len(header_value) == 0 {
				log.error("Header value has no length")
				return header, false
			}

			value, ok := strconv.parse_int(header_value)

			if !ok {
				log.error("Failed to parse content length value")
				return header, false
			}

			header.content_length = value

			found_content_length = true
		} else if strings.compare(header_name, "Content-Type") == 0 {
			if len(header_value) == 0 {
				log.error("Header value has no length")
				return header, false
			}
		}
	}

	return header, found_content_length
}

read_and_parse_body :: proc(reader: ^Reader, header: Header) -> (json.Value, bool) {
	value: json.Value

	data := make([]u8, header.content_length, context.temp_allocator)

	if !read_sized(reader, data) {
		log.error("Failed to read body")
		return value, false
	}

	err: json.Error

	value, err = json.parse(data = data, allocator = context.allocator, parse_integers = true)

	if (err != json.Error.None) {
		log.error("Failed to parse body")
		return value, false
	}

	return value, true
}

call_map: map[string]proc(_: json.Value, _: RequestId, _: ^common.Config, _: ^Writer) -> common.Error = {
	"initialize"                        = request_initialize,
	"initialized"                       = request_initialized,
	"shutdown"                          = request_shutdown,
	"exit"                              = notification_exit,
	"textDocument/didOpen"              = notification_did_open,
	"textDocument/didChange"            = notification_did_change,
	"textDocument/didClose"             = notification_did_close,
	"textDocument/didSave"              = notification_did_save,
	"textDocument/definition"           = request_definition,
	"textDocument/typeDefinition"       = request_type_definition,
	"textDocument/completion"           = request_completion,
	"textDocument/signatureHelp"        = request_signature_help,
	"textDocument/documentSymbol"       = request_document_symbols,
	"textDocument/semanticTokens/full"  = request_semantic_token_full,
	"textDocument/semanticTokens/range" = request_semantic_token_range,
	"textDocument/hover"                = request_hover,
	"textDocument/formatting"           = request_format_document,
	"textDocument/inlayHint"            = request_inlay_hint,
	"textDocument/documentLink"         = request_document_links,
	"textDocument/rename"               = request_rename,
	"textDocument/prepareRename"        = request_prepare_rename,
	"textDocument/references"           = request_references,
	"textDocument/documentHighlight"    = request_highlights,
	"textDocument/codeAction"           = request_code_action,
	"window/progress"                   = request_noop,
	"workspace/symbol"                  = request_workspace_symbols,
	"workspace/didChangeConfiguration"  = notification_workspace_did_change_configuration,
	"workspace/didChangeWatchedFiles"   = notification_did_change_watched_files,
}

notification_map: map[string]struct{} = {
	"textDocument/didOpen"            = {},
	"textDocument/didChange"          = {},
	"textDocument/didClose"           = {},
	"textDocument/didSave"            = {},
	"initialized"                     = {},
	"window/progress"                 = {},
	"workspace/didChangeWatchedFiles" = {},
}

consume_requests :: proc(config: ^common.Config, writer: ^Writer) -> bool {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)

	requests_copy := make([dynamic]Request)

	{
		sync.mutex_lock(&requests_mutex)
		defer sync.mutex_unlock(&requests_mutex)

		for d in deletings {
			delete_index := -1
			for request, i in requests {
				if request.id == d.id {
					delete_index = i
					break
				}
			}
			if delete_index != -1 {
				req := requests[delete_index]
				json_value := req.value
				cancel(json_value, req.id, writer, config)
				ordered_remove(&requests, delete_index)

				json.destroy_value(json_value, allocator = req.allocator)
			}
		}

		for request in requests {
			assert(request.value != nil)
			append(&requests_copy, request)
		}
	}

	request_index := 0

	for ; request_index < len(requests_copy); request_index += 1 {
		request := requests_copy[request_index]
		call(request.value, request.id, writer, config)

		json.destroy_value(request.value, allocator = request.allocator)
	}

	{
		sync.mutex_lock(&requests_mutex)
		defer sync.mutex_unlock(&requests_mutex)

		for i := 0; i < request_index; i += 1 {
			pop_front(&requests)
		}
	}


	if request_index != len(requests_copy) {
		sync.sema_post(&requests_sempahore)
	}

	if common.config.running {
		sync.sema_wait(&requests_sempahore)
	}

	return true
}


cancel :: proc(value: json.Value, id: RequestId, writer: ^Writer, config: ^common.Config) {
	response := make_response_message(id = id, params = ResponseParams{})
	send_response(response, writer)
}

call :: proc(value: json.Value, id: RequestId, writer: ^Writer, config: ^common.Config) {
	root := value.(json.Object)

	method, ok := root["method"].(json.String)

	if !ok {
		log.errorf("Failed to find method: %#v", root)
		response := make_response_message_error(id = id, error = ResponseError{code = .MethodNotFound, message = ""})
		send_error(response, writer)
		return
	}

	diff: time.Duration
	{
		time.SCOPED_TICK_DURATION(&diff)

		if fn, ok := call_map[method]; !ok {
			response := make_response_message_error(
				id = id,
				error = ResponseError{code = .MethodNotFound, message = ""},
			)
			send_error(response, writer)
		} else {
			err := fn(root["params"], id, config, writer)
			if err != .None {
				response := make_response_message_error(id = id, error = ResponseError{code = err, message = ""})
				send_error(response, writer)
			}
		}
	}

	//log.errorf("time duration %v for %v", time.duration_milliseconds(diff), method)
}

read_ols_initialize_options :: proc(config: ^common.Config, ols_config: OlsConfig, project_path: string) {
	config.disable_parser_errors = ols_config.disable_parser_errors.(bool) or_else config.disable_parser_errors
	config.thread_count = ols_config.thread_pool_count.(int) or_else config.thread_count
	config.enable_document_symbols = ols_config.enable_document_symbols.(bool) or_else config.enable_document_symbols
	config.enable_format = ols_config.enable_format.(bool) or_else config.enable_format
	config.enable_hover = ols_config.enable_hover.(bool) or_else config.enable_hover
	config.enable_semantic_tokens = ols_config.enable_semantic_tokens.(bool) or_else config.enable_semantic_tokens
	config.enable_unused_imports_reporting =
		ols_config.enable_unused_imports_reporting.(bool) or_else config.enable_unused_imports_reporting
	config.enable_procedure_context =
		ols_config.enable_procedure_context.(bool) or_else config.enable_procedure_context
	config.enable_snippets = ols_config.enable_snippets.(bool) or_else config.enable_snippets
	config.enable_references = ols_config.enable_references.(bool) or_else config.enable_references
	config.enable_document_highlights =
		ols_config.enable_document_highlights.(bool) or_else config.enable_document_highlights
	config.enable_completion_matching =
		ols_config.enable_completion_matching.(bool) or_else config.enable_completion_matching
	config.enable_document_links = ols_config.enable_document_links.(bool) or_else config.enable_document_links
	config.enable_comp_lit_signature_help =
		ols_config.enable_comp_lit_signature_help.(bool) or_else config.enable_comp_lit_signature_help
	config.enable_comp_lit_signature_help_use_docs =
		ols_config.enable_comp_lit_signature_help_use_docs.(bool) or_else config.enable_comp_lit_signature_help_use_docs
	config.verbose = ols_config.verbose.(bool) or_else config.verbose

	config.enable_procedure_snippet =
		ols_config.enable_procedure_snippet.(bool) or_else config.enable_procedure_snippet

	config.enable_auto_import = ols_config.enable_auto_import.(bool) or_else config.enable_auto_import

	config.enable_checker_only_saved =
		ols_config.enable_checker_only_saved.(bool) or_else config.enable_checker_only_saved

	if ols_config.odin_command != "" {
		config.odin_command = strings.clone(ols_config.odin_command, context.temp_allocator)

		allocated: bool
		config.odin_command, allocated = common.resolve_home_dir(config.odin_command)
		if !allocated {
			config.odin_command = strings.clone(config.odin_command, context.allocator)
		}
	}

	if ols_config.odin_root_override != "" {
		config.odin_root_override = strings.clone(ols_config.odin_root_override, context.temp_allocator)

		allocated: bool
		config.odin_root_override, allocated = common.resolve_home_dir(config.odin_root_override)
		if !allocated {
			config.odin_root_override = strings.clone(config.odin_root_override, context.allocator)
		}
	}

	if ols_config.checker_args != "" {
		config.checker_args = strings.clone(ols_config.checker_args, common.config_storage.allocator)
	}

	for profile in ols_config.profiles {
		if ols_config.profile == profile.name {
			config.profile.checker_path = make([dynamic]string, len(profile.checker_path), common.config_storage.allocator)
			config.profile.exclude_path = make([dynamic]string, len(profile.exclude_path), common.config_storage.allocator)

			for checker_path, i in profile.checker_path {
				config.profile.checker_path[i] = path.join(elems = {project_path, checker_path}, allocator = common.config_storage.allocator)
			}
			for exclude_path, i in profile.exclude_path {
				config.profile.exclude_path[i] = path.join(elems = {project_path, exclude_path}, allocator = common.config_storage.allocator)
			}

			config.profile.os = strings.clone(profile.os, common.config_storage.allocator)
			config.profile.arch = strings.clone(profile.arch, common.config_storage.allocator)

			for key, value in profile.defines {
				config.profile.defines[strings.clone(key, common.config_storage.allocator)] = strings.clone(value, common.config_storage.allocator)
			}

			break
		}
	}

	if config.profile.os == "" {
		config.profile.os = analysis.os_enum_to_string[ODIN_OS]
	}

	if config.profile.arch == "" {
		config.profile.arch = fmt.aprint(ODIN_ARCH)
	}

	config.checker_targets = slice.clone(ols_config.checker_targets, context.allocator)

	config.enable_inlay_hints_params =
		ols_config.enable_inlay_hints_params.(bool) or_else config.enable_inlay_hints_params
	config.enable_inlay_hints_default_params =
		ols_config.enable_inlay_hints_default_params.(bool) or_else config.enable_inlay_hints_default_params
	config.enable_inlay_hints_implicit_return =
		ols_config.enable_inlay_hints_implicit_return.(bool) or_else config.enable_inlay_hints_implicit_return

	config.enable_fake_method = ols_config.enable_fake_methods.(bool) or_else config.enable_fake_method
	config.enable_overload_resolution =
		ols_config.enable_overload_resolution.(bool) or_else config.enable_overload_resolution
	config.enable_invert_if_diagnostics =
		ols_config.enable_invert_if_diagnostics.(bool) or_else config.enable_invert_if_diagnostics

	// Delete overriding collections.
	for it in ols_config.collections {
		overrides := make([dynamic]string)
		defer delete(overrides)
		for k, v in config.collections {
			if it.name == k {
				append(&overrides, k)
			}
		}
		for k in overrides {
			delete(config.collections[k])
			delete_key(&config.collections, k)
			delete(k)
		}
	}

	// Apply custom collections.
	for it in ols_config.collections {
		forward_path, _ := filepath.to_slash(it.path, context.temp_allocator)

		forward_path = common.resolve_home_dir(forward_path, context.temp_allocator)

		final_path := ""

		when ODIN_OS == .Windows {
			if filepath.is_abs(it.path) {
				final_path, _ = filepath.to_slash(
					common.get_case_sensitive_path(forward_path, context.temp_allocator),
					context.temp_allocator,
				)
			} else {
				final_path, _ = filepath.to_slash(
					common.get_case_sensitive_path(
						path.join(elems = {project_path, forward_path}, allocator = context.temp_allocator),
						context.temp_allocator,
					),
					context.temp_allocator,
				)
			}

			final_path = strings.clone(final_path, context.temp_allocator)
		} else {
			if filepath.is_abs(it.path) {
				final_path = strings.clone(forward_path, context.temp_allocator)
			} else {
				final_path = path.join({project_path, forward_path}, context.temp_allocator)
			}
		}

		if abs_final_path, ok := filepath.abs(final_path); ok {
			slashed_path, _ := filepath.to_slash(abs_final_path, context.temp_allocator)

			config.collections[strings.clone(it.name, common.config_storage.allocator)] = strings.clone(
				slashed_path,
				common.config_storage.allocator,
			)
		} else {
			log.errorf("Failed to find absolute address of collection: %v", final_path)
			config.collections[strings.clone(it.name, common.config_storage.allocator)] = strings.clone(
				final_path,
				common.config_storage.allocator,
			)
		}
	}

	// Ideally we'd disallow specifying the builtin `base`, `core` and `vendor` completely
	// because using `odin root` is always correct, but I suspect a lot of people have this in
	// their config and it would break.

	odin_core_env: string
	if config.odin_root_override != "" {
		odin_core_env = config.odin_root_override
	} else {
		odin_bin := "odin" if config.odin_command == "" else config.odin_command

		// If we don't have an absolute path
		if !filepath.is_abs(odin_bin) {
			// Join with the project path
			tmp_path := path.join(elems = {project_path, odin_bin})
			if os.exists(tmp_path) {
				odin_bin = tmp_path
			}
		}

		root_buf: [1024]byte
		root_slice := root_buf[:]
		root_command := strings.concatenate({odin_bin, " root"}, context.temp_allocator)
		code, ok, out := common.run_executable(root_command, &root_slice)
		if ok && !strings.contains(string(out), "Usage") {
			odin_core_env = string(out)
		} else {
			log.warnf("failed executing %q with code %v", root_command, code)

			// User is probably on an older Odin version, let's try our best.

			odin_core_env = os.get_env("ODIN_ROOT", context.temp_allocator)
			if odin_core_env == "" {
				if os.exists(odin_bin) {
					odin_core_env = filepath.dir(odin_bin, context.temp_allocator)
				} else if exe_path, ok := common.lookup_in_path(odin_bin); ok {
					odin_core_env = filepath.dir(exe_path, context.temp_allocator)
				}
			}

			if odin_core_env != "" {
				if abs_core_env, ok := filepath.abs(odin_core_env, context.temp_allocator); ok {
					odin_core_env = abs_core_env
				}
			}
		}
	}

	log.infof("resolved odin root to: %q", odin_core_env)
	log.infof("project path: %q", project_path)

	// Insert the default collections if they are not specified in the config.
	if odin_core_env != "" {
		forward_path, _ := filepath.to_slash(odin_core_env, context.temp_allocator)
		initialize_default_collections(config, forward_path)
	}

	log.info(config.collections)
}

get_odin_directory :: proc(allocator := context.allocator) -> string {
	root_buf: [1024]byte
	root_slice := root_buf[:]
	root_command := strings.concatenate({"odin", " root"})
	code, ok, out := common.run_executable(root_command, &root_slice)
	if ok && !strings.contains(string(out), "Usage") {
		return strings.clone(string(out), allocator)
	}
	return ""
}

initialize_default_collections :: proc(config: ^common.Config, collections_dir: string = "") {
	forward_path := collections_dir
	forward_path = forward_path if forward_path != "" else get_odin_directory(common.config_storage.allocator)

	// base
	if "base" not_in config.collections {
		config.collections[strings.clone("base", common.config_storage.allocator)] = path.join(
			elems = {forward_path, "base"},
			allocator = common.config_storage.allocator,
		)
	}

	// core
	if "core" not_in config.collections {
		config.collections[strings.clone("core", common.config_storage.allocator)] = path.join(
			elems = {forward_path, "core"},
			allocator = common.config_storage.allocator,
		)
	}

	// vendor
	if "vendor" not_in config.collections {
		config.collections[strings.clone("vendor", common.config_storage.allocator)] = path.join(
			elems = {forward_path, "vendor"},
			allocator = common.config_storage.allocator,
		)
	}

	// shared
	if "shared" not_in config.collections {
		shared_path := path.join(elems = {forward_path, "shared"}, allocator = common.config_storage.allocator)
		if os.exists(shared_path) {
			config.collections[strings.clone("shared", common.config_storage.allocator)] = shared_path
		} else {
			delete(shared_path, common.config_storage.allocator)
		}
	}
}

request_initialize :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	initialize_params: RequestInitializeParams

	if err := unmarshal(params, initialize_params, context.temp_allocator); err != nil {
		return .ParseError
	}

	config.client_name = strings.clone(initialize_params.clientInfo.name, common.config_storage.allocator)

	for s in initialize_params.workspaceFolders {
		workspace: common.WorkspaceFolder
		workspace.uri = common.clone_uri(s.uri, common.config_storage.allocator)
		append(&config.workspace_folders, workspace)
	}

	config.enable_hover = true
	config.enable_format = true

	config.enable_inlay_hints_params = false
	config.enable_inlay_hints_default_params = false
	config.enable_inlay_hints_implicit_return = false

	config.disable_parser_errors = false
	config.thread_count = 2
	config.enable_document_symbols = true
	config.enable_format = true
	config.enable_hover = true
	config.enable_semantic_tokens = false
	config.enable_unused_imports_reporting = true
	config.enable_procedure_context = false
	config.enable_snippets = false
	config.enable_references = true
	config.enable_document_highlights = true
	config.enable_completion_matching = true
	config.enable_document_links = true
	config.enable_comp_lit_signature_help = false
	config.verbose = false
	config.odin_command = ""
	config.checker_args = ""
	config.enable_fake_method = false
	config.enable_procedure_snippet = true
	config.enable_checker_only_saved = true
	config.enable_auto_import = true
	config.enable_invert_if_diagnostics = true

	read_ols_config :: proc(file: string, config: ^common.Config, path: string) {
		if data, ok := os.read_entire_file(file, context.temp_allocator); ok {
			ols_config: OlsConfig

			err := json.unmarshal(data, &ols_config, allocator = context.temp_allocator)
			if err == nil {
				read_ols_initialize_options(config, ols_config, path)
			} else {
				log.errorf("Failed to unmarshal %v: %v", file, err)
			}
		} else {
			log.warnf("Failed to read/find %v", file)
		}
	}

	encoded_project_path := common.FileUri("")

	if len(config.workspace_folders) > 0 {
		encoded_project_path = config.workspace_folders[0].uri
	} else if initialize_params.rootUri != "" {
		encoded_project_path = common.path_to_uri(initialize_params.rootUri, common.config_storage.allocator)
	}

	if project_path, ok := common.uri_to_path(encoded_project_path, context.temp_allocator); ok {
		// Apply the global ols config.
		global_ols_config_path := path.join(
			elems = {filepath.dir(os.args[0], context.temp_allocator), "ols.json"},
			allocator = context.temp_allocator,
		)
		read_ols_config(global_ols_config_path, config, project_path)

		// Apply the requested ols config.
		read_ols_initialize_options(config, initialize_params.initializationOptions, project_path)

		// Apply ols.json config.
		ols_config_path := path.join(elems = {project_path, "ols.json"}, allocator = context.temp_allocator)
		read_ols_config(ols_config_path, config, project_path)
	} else {
		read_ols_initialize_options(config, initialize_params.initializationOptions, "")
	}

	for format in initialize_params.capabilities.textDocument.hover.contentFormat {
		if format == "markdown" {
			config.hover_support_md = true
		}
	}

	for format in initialize_params.capabilities.textDocument.completion.documentationFormat {
		if format == "markdown" {
			config.completion_support_md = true
		}
	}

	config.enable_label_details =
		initialize_params.capabilities.textDocument.completion.completionItem.labelDetailsSupport

	config.enable_snippets &= initialize_params.capabilities.textDocument.completion.completionItem.snippetSupport

	config.signature_offset_support =
		initialize_params.capabilities.textDocument.signatureHelp.signatureInformation.parameterInformation.labelOffsetSupport

	completionTriggerCharacters := []string{".", ">", "#", "\"", "/", ":"}
	signatureTriggerCharacters := []string{"(", ","}
	signatureRetriggerCharacters := []string{","}

	semantic_range_support := initialize_params.capabilities.textDocument.semanticTokens.requests.range

	response := make_response_message(
		params = ResponseInitializeParams {
			capabilities = ServerCapabilities {
				textDocumentSync = TextDocumentSyncOptions{openClose = true, change = 2, save = {includeText = true}},
				renameProvider = RenameOptions{prepareProvider = true},
				workspaceSymbolProvider = true,
				referencesProvider = config.enable_references,
				documentHighlightProvider = config.enable_document_highlights,
				definitionProvider = true,
				typeDefinitionProvider = true,
				completionProvider = CompletionOptions {
					resolveProvider = false,
					triggerCharacters = completionTriggerCharacters,
					completionItem = {labelDetailsSupport = true},
				},
				signatureHelpProvider = SignatureHelpOptions {
					triggerCharacters = signatureTriggerCharacters,
					retriggerCharacters = signatureRetriggerCharacters,
				},
				semanticTokensProvider = SemanticTokensOptions {
					range = config.enable_semantic_tokens && semantic_range_support,
					full = config.enable_semantic_tokens,
					legend = SemanticTokensLegend {
						tokenTypes = semantic_token_type_names,
						tokenModifiers = semantic_token_modifier_names,
					},
				},
				inlayHintProvider = (config.enable_inlay_hints_params ||
					config.enable_inlay_hints_default_params ||
					config.enable_inlay_hints_implicit_return),
				documentSymbolProvider = config.enable_document_symbols,
				hoverProvider = config.enable_hover,
				documentFormattingProvider = config.enable_format,
				documentLinkProvider = {resolveProvider = false},
				codeActionProvider = {resolveProvider = false, codeActionKinds = {"refactor.rewrite"}},
			},
		},
		id = id,
	)

	send_response(response, writer)

	if initialize_params.capabilities.workspace.didChangeWatchedFiles.dynamicRegistration {
		register_dynamic_capabilities(writer)
	}

	return .None
}

register_dynamic_capabilities :: proc(writer: ^Writer) {
	params: RegistrationParams

	registration: Registration

	registration.id = "GLOBAL_ODIN_FILES"
	registration.method = "workspace/didChangeWatchedFiles"
	registration.registerOptions = DidChangeWatchedFilesRegistrationOptions {
		watchers = []FileSystemWatcher{{globPattern = "**/*.odin"}},
	}

	params.registrations = {registration}

	request_message := RequestMessage {
		jsonrpc = "2.0",
		method  = "client/registerCapability",
		params  = params,
		id      = "REGISTER_DYNAMIC_CAPABILITIES",
	}

	send_request(request_message, writer)
}

request_initialized :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	return .None
}

request_shutdown :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	response := make_response_message(params = nil, id = id)

	send_response(response, writer)

	return .None
}

request_definition :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	definition_params: TextDocumentPositionParams

	if unmarshal(params, definition_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(definition_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	req_ctx, ctx_ok := make_request_context(document, definition_params.position, config)
	if !ctx_ok {
		return .InternalError
	}

	locations, ok2 := get_definition_location(&req_ctx)

	if !ok2 {
		log.warn("Failed to get definition location")
	}

	if len(locations) == 1 {
		response := make_response_message(params = locations[0], id = id)
		send_response(response, writer)
	} else {
		response := make_response_message(params = locations, id = id)
		send_response(response, writer)
	}

	return .None
}

request_type_definition :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	definition_params: TextDocumentPositionParams

	if unmarshal(params, definition_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(definition_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	req_ctx, ctx_ok := make_request_context(document, definition_params.position, config)
	if !ctx_ok {
		return .InternalError
	}

	locations, ok2 := get_type_definition_locations(&req_ctx)
	if !ok2 {
		log.warn("Failed to get type definition location")
	}

	if len(locations) == 1 {
		response := make_response_message(params = locations[0], id = id)
		send_response(response, writer)
	} else {
		response := make_response_message(params = locations, id = id)
		send_response(response, writer)
	}

	return .None
}

request_completion :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	completition_params: CompletionParams

	if unmarshal(params, completition_params, context.temp_allocator) != nil {
		log.error("Failed to unmarshal completion request")
		return .ParseError
	}

	filepath := common.uri_to_path(completition_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	req_ctx, ctx_ok := make_request_context(document, completition_params.position, config)
	if !ctx_ok {
		return .InternalError
	}

	list: CompletionList
	list, ok = get_completion_list(&req_ctx, completition_params.context_)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = list, id = id)

	send_response(response, writer)

	return .None
}

request_signature_help :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	signature_params: SignatureHelpParams

	if unmarshal(params, signature_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(signature_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	req_ctx, ctx_ok := make_request_context(document, signature_params.position, config)
	if !ctx_ok {
		return .InternalError
	}

	help: SignatureHelp
	help, ok = get_signature_information(&req_ctx)

	if !ok {
		return .InternalError
	}

	if len(help.signatures) == 0 {
		response := make_response_message(params = nil, id = id)
		send_response(response, writer)
	} else {
		response := make_response_message(params = help, id = id)
		send_response(response, writer)
	}


	return .None
}

request_format_document :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	format_params: DocumentFormattingParams

	if unmarshal(params, format_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(format_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	edit: []TextEdit
	edit, ok = get_complete_format(doc_ctx, config)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = edit, id = id)

	send_response(response, writer)

	return .None
}

notification_exit :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	config.running = false
	return .None
}

notification_did_open :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		log.error("Failed to parse open document notification")
		return .ParseError
	}

	open_params: DidOpenTextDocumentParams

	if unmarshal(params, open_params, context.allocator) != nil {
		log.error("Failed to parse open document notification")
		return .ParseError
	}

	defer delete(string(open_params.textDocument.uri))

	filepath := common.uri_to_path(open_params.textDocument.uri, context.temp_allocator)
	document := doc.open(filepath, open_params.textDocument.text) or_return

	if doc_ctx, ctx_ok := create_document_context(document, config); ctx_ok {
		// Update the symbol cache with the document's symbols
		analysis.update_doc(doc_ctx.syntaxTree)

		// Run lightweight diagnostics
		check_unused_imports(doc_ctx, config)
		check_invert_if_suggestions(doc_ctx, config)
	}

	// Publish any dirty diagnostics
	publish_diagnostics(writer)

	return .None
}

notification_did_change :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	change_params: DidChangeTextDocumentParams

	if unmarshal(params, change_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(change_params.textDocument.uri, context.temp_allocator)
	document_apply_changes(
		filepath,
		change_params.contentChanges,
		change_params.textDocument.version,
		config,
		writer,
	)

	// Update the symbol cache and run lightweight diagnostics
	document := document_get(filepath)
	if document != nil {
		if doc_ctx, ctx_ok := create_document_context(document, config); ctx_ok {
			analysis.update_doc(doc_ctx.syntaxTree)

			// Run lightweight AST-based diagnostics on edit for immediate feedback
			// (full odin check only runs on save as it's too expensive for every keystroke)
			check_unused_imports(doc_ctx, config)
			check_invert_if_suggestions(doc_ctx, config)
		}
	}

	// Publish any dirty diagnostics
	publish_diagnostics(writer)

	return .None
}

notification_did_close :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	close_params: DidCloseTextDocumentParams

	if unmarshal(params, close_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(close_params.textDocument.uri, context.temp_allocator)
	if n := document_close(filepath); n != nil {
		return .InternalError
	}

	return .None
}

notification_did_save :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	save_params: DidSaveTextDocumentParams

	if unmarshal(params, save_params, context.temp_allocator) != nil {
		return .ParseError
	}

	path: string

	if path, ok = common.uri_to_path(save_params.textDocument.uri, context.temp_allocator); !ok {
		return .ParseError
	}

	fullpath := path

	when ODIN_OS == .Windows {
		correct := common.get_case_sensitive_path(fullpath, context.temp_allocator)
		fullpath, _ = filepath.to_slash(correct, context.temp_allocator)
	}

	corrected_encoded_path := common.path_to_uri(fullpath, context.temp_allocator)

	// Run odin check - this clears old .Check diagnostics and adds new ones
	filepath_for_get := common.uri_to_path(save_params.textDocument.uri, context.temp_allocator)
	check(config.profile.checker_path[:], corrected_encoded_path, config)

	document := document_get(filepath_for_get)
	if document != nil {
		if doc_ctx, ctx_ok := create_document_context(document, config); ctx_ok {
			// Run lightweight diagnostics for the current document
			check_unused_imports(doc_ctx, config)
			check_invert_if_suggestions(doc_ctx, config)
		}
	}

	// Publish all dirty diagnostics
	publish_diagnostics(writer)

	return .None
}

request_semantic_token_full :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	semantic_params: SemanticTokensParams

	if unmarshal(params, semantic_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(semantic_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	range := common.Range {
		start = common.Position{line = 0},
		end = common.Position{line = 9000000}, //should be enough
	}

	tokens_params: SemanticTokensResponseParams

	if config.enable_semantic_tokens {
		doc_ctx, ctx_ok := create_document_context(document, config)
		if ctx_ok {
			file := FileResolve {
				symbols = resolve_entire_file(doc_ctx),
			}
			tokens := get_semantic_tokens(doc_ctx, range, file.symbols)
			tokens_params = semantic_tokens_to_response_params(tokens)
		}
	}

	response := make_response_message(params = tokens_params, id = id)

	send_response(response, writer)

	return .None
}

request_semantic_token_range :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .None
	}

	semantic_params: SemanticTokensRangeParams

	if unmarshal(params, semantic_params, context.temp_allocator) != nil {
		return .None
	}

	fullpath := common.uri_to_path(semantic_params.textDocument.uri, context.temp_allocator)
	document := document_get(fullpath)

	if document == nil {
		return .InternalError
	}

	tokens_params: SemanticTokensResponseParams

	if config.enable_semantic_tokens {
		doc_ctx, ctx_ok := create_document_context(document, config)
		if ctx_ok {
			file := FileResolve {
				symbols = resolve_ranged_file(doc_ctx, semantic_params.range),
			}
			tokens := get_semantic_tokens(doc_ctx, semantic_params.range, file.symbols)
			tokens_params = semantic_tokens_to_response_params(tokens)
		}
	}

	response := make_response_message(params = tokens_params, id = id)

	send_response(response, writer)

	return .None
}

request_document_symbols :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	symbol_params: DocumentSymbolParams

	if unmarshal(params, symbol_params, context.temp_allocator) != nil {
		return .ParseError
	}

	fullpath := common.uri_to_path(symbol_params.textDocument.uri, context.temp_allocator)
	document := document_get(fullpath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	symbols := get_document_symbols(doc_ctx)

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_hover :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	hover_params: HoverParams

	if unmarshal(params, hover_params, context.temp_allocator) != nil {
		return .ParseError
	}

	fullpath := common.uri_to_path(hover_params.textDocument.uri, context.temp_allocator)
	document := document_get(fullpath)

	if document == nil {
		return .InternalError
	}

	req_ctx, ctx_ok := make_request_context(document, hover_params.position, config)
	if !ctx_ok {
		return .InternalError
	}

	hover: Hover
	valid: bool
	hover, valid, ok = get_hover_information(&req_ctx)

	if !ok {
		return .InternalError
	}

	if valid {
		response := make_response_message(params = hover, id = id)
		send_response(response, writer)
	} else {
		response := make_response_message(params = nil, id = id)
		send_response(response, writer)
	}

	return .None
}

request_inlay_hint :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {

	_, is_params_object := params.(json.Object)
	if !is_params_object do return .ParseError

	inlay_params: InlayParams
	if unmarshal(params, inlay_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(inlay_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)
	if document == nil do return .InternalError

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok do return .InternalError

	file := FileResolve {
		symbols = resolve_ranged_file(doc_ctx, inlay_params.range),
	}

	hints, hints_ok := get_inlay_hints(doc_ctx, inlay_params.range, file.symbols, config)
	if !hints_ok do return .InternalError

	response := make_response_message(params = hints, id = id)
	send_response(response, writer)

	return .None
}

request_document_links :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	if !config.enable_document_links {
		links: []DocumentLink
		response := make_response_message(params = links, id = id)

		send_response(response, writer)
		return .None
	}

	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	link_params: DocumentLinkParams

	if unmarshal(params, link_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(link_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	links: []DocumentLink
	links, ok = get_document_links(doc_ctx)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = links, id = id)

	send_response(response, writer)

	return .None
}

request_prepare_rename :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	rename_param: PrepareRenameParams

	if unmarshal(params, rename_param, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(rename_param.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	if range, ok := get_prepare_rename(doc_ctx, rename_param.position); ok {
		response := make_response_message(params = range, id = id)
		send_response(response, writer)
	} else {
		response := make_response_message(params = nil, id = id)
		send_response(response, writer)
	}

	return .None
}

request_rename :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	rename_param: RenameParams

	if unmarshal(params, rename_param, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(rename_param.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	workspace_edit: WorkspaceEdit
	workspace_edit, ok = get_rename(doc_ctx, rename_param.newName, rename_param.position)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = workspace_edit, id = id)

	send_response(response, writer)

	return .None
}

request_references :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	reference_param: ReferenceParams

	if unmarshal(params, reference_param, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(reference_param.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	locations: []common.Location
	locations, ok = get_references(doc_ctx, reference_param.position)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = locations, id = id)

	send_response(response, writer)

	return .None
}

request_highlights :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	highlight_param: HighlightParams

	if unmarshal(params, highlight_param, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(highlight_param.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	locations: []common.Location
	locations, ok = get_references(doc_ctx, highlight_param.position, true)

	if !ok {
		return .InternalError
	}

	highlights := make([dynamic]DocumentHighlight, 0, context.temp_allocator)
	for location in locations {
		append(&highlights, DocumentHighlight{kind = .Text, range = location.range})
	}

	response := make_response_message(params = highlights[:], id = id)

	send_response(response, writer)

	return .None
}

request_code_action :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	code_action_params: CodeActionParams

	if unmarshal(params, code_action_params, context.temp_allocator) != nil {
		return .ParseError
	}

	filepath := common.uri_to_path(code_action_params.textDocument.uri, context.temp_allocator)
	document := document_get(filepath)

	if document == nil {
		return .InternalError
	}

	doc_ctx, ctx_ok := create_document_context(document, config)
	if !ctx_ok {
		return .InternalError
	}

	code_actions: []CodeAction
	code_actions, ok = get_code_actions(doc_ctx, code_action_params.range, config)
	if !ok {
		return .InternalError
	}
	response := make_response_message(params = code_actions, id = id)

	send_response(response, writer)

	return .None
}

notification_did_change_watched_files :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	did_change_watched_files_params: DidChangeWatchedFilesParams

	if unmarshal(params, did_change_watched_files_params, context.temp_allocator) != nil {
		return .ParseError
	}

	// No global index to update - symbols are built fresh per request

	return .None
}

notification_workspace_did_change_configuration :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	workspace_config_params: DidChangeConfigurationParams

	if unmarshal(params, workspace_config_params, context.temp_allocator) != nil {
		return .ParseError
	}

	ols_config := workspace_config_params.settings

	if project_path, ok := common.uri_to_path(config.workspace_folders[0].uri, context.temp_allocator); ok {
		read_ols_initialize_options(config, ols_config, project_path)
	}

	return .None
}

request_workspace_symbols :: proc(
	params: json.Value,
	id: RequestId,
	config: ^common.Config,
	writer: ^Writer,
) -> common.Error {
	params_object, ok := params.(json.Object)

	if !ok {
		return .ParseError
	}

	workspace_symbol_params: WorkspaceSymbolParams

	if unmarshal(params, workspace_symbol_params, context.temp_allocator) != nil {
		return .ParseError
	}

	symbols: []WorkspaceSymbol
	symbols, ok = get_workspace_symbols(workspace_symbol_params.query)

	if !ok {
		return .InternalError
	}

	response := make_response_message(params = symbols, id = id)

	send_response(response, writer)

	return .None
}

request_noop :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
	return .None
}
