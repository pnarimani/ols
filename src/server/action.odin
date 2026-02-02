package server

import "src:documents"
import "core:fmt"
import "core:log"
import "core:odin/ast"
import path "core:path/slashpath"
import "core:strings"

import "src:analysis"
import "src:common"

CodeActionKind :: string

CodeActionClientCapabilities :: struct {
	codeActionLiteralSupport: struct {
		codeActionKind: struct {
			valueSet: [dynamic]CodeActionKind,
		},
	},
}

CodeActionOptions :: struct {
	codeActionKinds: []CodeActionKind,
	resolveProvider: bool,
}

CodeActionParams :: struct {
	textDocument: TextDocumentIdentifier,
	range:        common.Range,
}

CodeAction :: struct {
	title:       string,
	kind:        CodeActionKind,
	isPreferred: bool,
	edit:        WorkspaceEdit,
}

get_code_actions :: proc(
	doc_ctx: documents.Document,
	range: common.Range,
	config: ^common.Config,
) -> (
	[]CodeAction,
	bool,
) {
	// Build symbol cache for this request's packages
	load_document_packages(doc_ctx)

	encoded_path := common.make_encoded_path(doc_ctx.path, context.temp_allocator)

	ast_context := make_ast_context(
		doc_ctx.ast,
		doc_ctx.imports,
		doc_ctx.package_name,
		encoded_path,
		doc_ctx.fullpath,
		context.temp_allocator,
	)

	position_context, ok := get_document_position_context(doc_ctx, range.start, .Hover)
	if !ok {
		log.warn("Failed to get position context")
		return {}, false
	}

	ast_context.position_hint = position_context.hint

	get_globals(doc_ctx.ast, &ast_context)

	ast_context.current_package = ast_context.document_package

	if position_context.function != nil {
		get_locals(doc_ctx.ast, position_context.function, &ast_context, &position_context)
	}

	actions := make([dynamic]CodeAction, 0, context.temp_allocator)

	if position_context.selector_expr != nil {
		if selector, ok := position_context.selector_expr.derived.(^ast.Selector_Expr); ok {
			add_missing_imports(
				&ast_context,
				selector,
				strings.clone(encoded_path, context.temp_allocator),
				config,
				&actions,
			)
		}
	} else if position_context.import_stmt != nil {
		remove_unused_imports(doc_ctx, strings.clone(encoded_path, context.temp_allocator), config, &actions)
	}

	add_invert_if_action(
		doc_ctx,
		position_context.position,
		strings.clone(encoded_path, context.temp_allocator),
		&actions,
	)
	add_redundant_else_action(
		doc_ctx,
		position_context.position,
		strings.clone(encoded_path, context.temp_allocator),
		&actions,
	)
	add_extract_proc_action(
		doc_ctx,
		&ast_context,
		range,
		strings.clone(encoded_path, context.temp_allocator),
		&actions,
	)
	add_extract_variable_action(
		doc_ctx,
		&ast_context,
		range,
		strings.clone(encoded_path, context.temp_allocator),
		&actions,
	)
	add_inline_proc_action(
		doc_ctx,
		&ast_context,
		range,
		strings.clone(encoded_path, context.temp_allocator),
		&actions,
	)
	add_inline_variable_action(
		doc_ctx,
		&ast_context,
		range,
		strings.clone(encoded_path, context.temp_allocator),
		&actions,
	)
	add_inline_alias_action(
		doc_ctx,
		&ast_context,
		config,
		range,
		strings.clone(encoded_path, context.temp_allocator),
		&actions,
	)

	return actions[:], true
}

remove_unused_imports :: proc(
	doc_ctx: documents.Document,
	uri: string,
	config: ^common.Config,
	actions: ^[dynamic]CodeAction,
) {
	unused_imports := find_unused_imports(doc_ctx, context.temp_allocator)

	if len(unused_imports) == 0 {
		return
	}

	textEdits := make([dynamic]TextEdit, context.temp_allocator)

	for imp in unused_imports {
		range := common.get_token_range(imp.import_decl, doc_ctx.ast.src)

		import_edit := TextEdit {
			range   = range,
			newText = "",
		}

		if (range.start.line != 1) {
			if column, ok := common.get_last_column(import_edit.range.start.line - 1, doc_ctx.text); ok {
				import_edit.range.start.line -= 1
				import_edit.range.start.character = column
			}

		}


		append(&textEdits, import_edit)
	}

	workspaceEdit: WorkspaceEdit
	workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
	workspaceEdit.changes[uri] = textEdits[:]

	append(
		actions,
		CodeAction {
			kind = "refactor.rewrite",
			isPreferred = true,
			title = fmt.tprint("remove unused imports"),
			edit = workspaceEdit,
		},
	)

}

add_missing_imports :: proc(
	ast_context: ^AstContext,
	selector: ^ast.Selector_Expr,
	uri: string,
	config: ^common.Config,
	actions: ^[dynamic]CodeAction,
) {
	if name, ok := selector.expr.derived.(^ast.Ident); ok {
		// If we already know what the name is referring to, don't prompt anything
		if _, ok := resolve_type_identifier(ast_context, name^); ok {
			return
		}
		pkg_aliases := find_all_package_aliases()
		for collection, pkgs in pkg_aliases {
			for pkg in pkgs {
				fullpath := path.join({config.collections[collection], pkg})
				found := false

				for doc_pkg in ast_context.imports {
					if fullpath == doc_pkg.name {
						found = true
					}
				}

				if found {
					continue
				}

				if pkg == name.name {
					pkg_decl := ast_context.file.pkg_decl
					import_edit := TextEdit {
						range = {
							start = {line = pkg_decl.end.line + 1, character = 0},
							end = {line = pkg_decl.end.line + 1, character = 0},
						},
						newText = fmt.tprintf("import \"%v:%v\"\n", collection, pkg),
					}
					textEdits := make([dynamic]TextEdit, context.temp_allocator)
					append(&textEdits, import_edit)

					workspaceEdit: WorkspaceEdit
					workspaceEdit.changes = make(map[string][]TextEdit, 0, context.temp_allocator)
					workspaceEdit.changes[uri] = textEdits[:]
					append(
						actions,
						CodeAction {
							kind = "refactor.rewrite",
							isPreferred = true,
							title = fmt.tprintf(`import package "%v:%v"`, collection, pkg),
							edit = workspaceEdit,
						},
					)
				}
			}
		}
	}

	return
}
