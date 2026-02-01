package common

import "core:mem"

ConfigProfile :: struct {
	os:           string,
	arch:         string,
	name:         string,
	checker_path: [dynamic]string,
	defines:      map[string]string,
	exclude_path: [dynamic]string,
}

Config :: struct {
	workspace_folders:                       [dynamic]WorkspaceFolder,
	completion_support_md:                   bool,
	hover_support_md:                        bool,
	signature_offset_support:                bool,
	collections:                             map[string]string,
	running:                                 bool,
	verbose:                                 bool,
	enable_format:                           bool,
	enable_hover:                            bool,
	enable_document_symbols:                 bool,
	enable_semantic_tokens:                  bool,
	enable_unused_imports_reporting:         bool,
	enable_inlay_hints_params:               bool,
	enable_inlay_hints_default_params:       bool,
	enable_inlay_hints_implicit_return:      bool,
	enable_procedure_context:                bool,
	enable_snippets:                         bool,
	enable_references:                       bool,
	enable_document_highlights:              bool,
	enable_label_details:                    bool,
	enable_std_references:                   bool,
	enable_import_fixer:                     bool,
	enable_fake_method:                      bool,
	enable_overload_resolution:              bool,
	enable_procedure_snippet:                bool,
	enable_checker_only_saved:               bool,
	enable_auto_import:                      bool,
	enable_completion_matching:              bool,
	enable_document_links:                   bool,
	enable_comp_lit_signature_help:          bool,
	enable_comp_lit_signature_help_use_docs: bool,
	enable_invert_if_diagnostics:            bool,
	disable_parser_errors:                   bool,
	thread_count:                            int,
	odin_command:                            string,
	odin_root_override:                      string,
	checker_args:                            string,
	checker_targets:                         []string,
	client_name:                             string,
	profile:                                 ConfigProfile,
}

ConfigStorage :: struct {
	allocator: mem.Allocator,
}

config_storage: ConfigStorage
config: Config

// Initialize config storage with a persistent allocator.
// Must be called before any config operations.
config_storage_init :: proc() {
	config_storage.allocator = context.allocator
	config.collections = make(map[string]string, config_storage.allocator)
	config.workspace_folders = make([dynamic]WorkspaceFolder, config_storage.allocator)
}

config_storage_shutdown :: proc() {
	for k, v in config.collections {
		delete(k, config_storage.allocator)
		delete(v, config_storage.allocator)
	}

	delete(config.collections)
	
	for ws in config.workspace_folders {
		delete(ws.uri, config_storage.allocator)
	}

	delete(config.workspace_folders)
}
