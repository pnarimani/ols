#+private file
#+feature dynamic-literals

package server

import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "src:documents"
import "src:workspace"

import "src:analysis"
import "src:common"

INLINE_ALIAS_ACTION_TITLE :: "Inline Alias"
INLINE_ALIAS_ACTION_KIND :: "refactor.inline"

// Track usages in other files
CrossFileUsage :: struct {
	fullpath:         string,
	source:           string,
	selector_usages:  [dynamic]^ast.Selector_Expr, // pkg.AliasName usages (cross-package)
	ident_usages:     [dynamic]^ast.Ident, // Direct AliasName usages (same-package)
	file:             ast.File,
	needs_import:     bool, // True if we need to add import for target_package
	import_alias:     string, // The alias to use for the import (e.g., "mem" or existing alias)
	existing_imports: []documents.Package,
	is_same_package:  bool, // True if this file is in the same package as the alias definition
}

InlineAliasContext :: struct {
	doc:                documents.Document,
	config:             ^common.Config,
	ast_context:        ^AstContext,
	position:           common.AbsolutePosition,
	// The alias declaration (Value_Decl with :: and no type)
	alias_decl:         ^ast.Value_Decl,
	// The name of the alias
	alias_name:         string,
	// The target type expression
	target_type:        ^ast.Expr,
	// All usages of the alias (identifiers that reference it) - in current file
	all_usages:         [dynamic]^ast.Ident,
	// If cursor is on a usage site, this is the specific usage to inline (nil = inline all from declaration)
	target_usage:       ^ast.Ident,
	// Package path extracted from target type (e.g., "core:mem" from mem.Arena)
	target_package:     string,
	// Original import specification for the target package (e.g., "core:mem")
	target_import_spec: string,
	// Selector in target type (e.g., "mem" from mem.Arena)
	target_selector:    string,
	// Cross-file usages
	cross_file_usages:  [dynamic]CrossFileUsage,
}

@(private = "package")
add_inline_alias_action :: proc(
	doc_ctx: documents.Document,
	ast_context: ^AstContext,
	config: ^common.Config,
	range: common.Range,
	uri: common.FileUri,
	actions: ^[dynamic]CodeAction,
) {
	// Only available for point selections (cursor), not range selections
	if range.start.line != range.end.line || range.start.character != range.end.character {
		return
	}

	ctx, ok := create_inline_alias_context(doc_ctx, ast_context, config, range.start)
	if !ok {
		return
	}
	defer destroy_inline_alias_context(&ctx)

	// Must have a target type
	if ctx.target_type == nil {
		return
	}

	// Must have at least one usage OR be on the declaration itself
	// When on the declaration, we always offer the action (usages may be in other files)
	is_on_declaration := ctx.alias_decl != nil && ctx.target_usage == nil
	if len(ctx.all_usages) == 0 && ctx.target_usage == nil && !is_on_declaration {
		return
	}

	edit, edit_ok := generate_inline_alias_edit(&ctx, uri)
	if !edit_ok {
		return
	}

	append(
		actions,
		CodeAction {
			kind = INLINE_ALIAS_ACTION_KIND,
			isPreferred = false,
			title = INLINE_ALIAS_ACTION_TITLE,
			edit = edit,
		},
	)
}

create_inline_alias_context :: proc(
	doc_ctx: documents.Document,
	ast_context: ^AstContext,
	config: ^common.Config,
	position: common.Position,
) -> (
	InlineAliasContext,
	bool,
) {
	ctx := InlineAliasContext {
		doc               = doc_ctx,
		config            = config,
		ast_context       = ast_context,
		all_usages        = make([dynamic]^ast.Ident, context.temp_allocator),
		cross_file_usages = make([dynamic]CrossFileUsage, context.temp_allocator),
	}

	abs_pos, ok := common.get_absolute_position(position, doc_ctx.text)
	if !ok {
		return ctx, false
	}
	ctx.position = abs_pos

	// First, try to find an alias declaration at the cursor position
	ctx.alias_decl, ctx.alias_name, ctx.target_type = find_alias_at_position(doc_ctx.ast.decls[:], abs_pos)

	if ctx.alias_decl != nil && ctx.alias_name != "" && ctx.target_type != nil {
		// Check if this is a distinct type - if so, block the action
		if is_distinct_alias(ctx.target_type) {
			return ctx, false
		}

		// Cursor is on declaration - inline all usages across all files
		// Extract package info from target type
		extract_package_info_from_type(&ctx)

		// Find all usages of this alias in all files
		find_all_alias_usages_in_workspace(&ctx, ctx.alias_name, &ctx.all_usages)

		// Find cross-file usages (other packages that reference this alias)
		find_cross_file_usages(&ctx)

		return ctx, true
	}

	// Try to find if cursor is on an alias usage (identifier in type context)
	ctx.target_usage = find_ident_at_position_in_type_context(doc_ctx.ast.decls[:], abs_pos)
	if ctx.target_usage == nil {
		return ctx, false
	}

	// Find the declaration for this identifier
	ctx.alias_name = ctx.target_usage.name
	ctx.alias_decl, ctx.target_type = find_alias_decl_by_name(doc_ctx.ast.decls[:], ast_context, ctx.alias_name)

	if ctx.alias_decl == nil || ctx.target_type == nil {
		return ctx, false
	}

	// Check if this is a distinct type - if so, block the action
	if is_distinct_alias(ctx.target_type) {
		return ctx, false
	}

	// Extract package info from target type
	extract_package_info_from_type(&ctx)

	return ctx, true
}

destroy_inline_alias_context :: proc(ctx: ^InlineAliasContext) {
	delete(ctx.all_usages)
	for &usage in ctx.cross_file_usages {
		delete(usage.selector_usages)
	}
	delete(ctx.cross_file_usages)
}

// Find an alias declaration at the given position
// Returns the Value_Decl, the alias name, and the target type expression
find_alias_at_position :: proc(
	decls: []^ast.Stmt,
	abs_pos: common.AbsolutePosition,
) -> (
	^ast.Value_Decl,
	string,
	^ast.Expr,
) {
	for decl in decls {
		if !position_in_node(decl, abs_pos) {
			continue
		}

		#partial switch d in decl.derived_stmt {
		case ^ast.Value_Decl:
			// Check if this is a type alias (has ::, no explicit type, has values)
			if len(d.names) != 1 || len(d.values) != 1 || d.type != nil {
				continue
			}

			// Get the alias name
			if name, ok := d.names[0].derived_expr.(^ast.Ident); ok {
				// The cursor should be on the LHS (name) part, not in the RHS (value) part
				// Check if cursor is before the start of the value expression
				if abs_pos <= int(d.values[0].pos.offset) {
					return d, name.name, d.values[0]
				}
			}
		}
	}

	return nil, "", nil
}

// Check if a type expression is a distinct type
is_distinct_alias :: proc(type_expr: ^ast.Expr) -> bool {
	if type_expr == nil {
		return false
	}

	#partial switch t in type_expr.derived_expr {
	case ^ast.Distinct_Type:
		return true
	}

	return false
}

// Extract package information from a type expression
// E.g., mem.Arena -> target_package = "core:mem", target_selector = "mem"
extract_package_info_from_type :: proc(ctx: ^InlineAliasContext) {
	if ctx.target_type == nil {
		return
	}

	#partial switch t in ctx.target_type.derived_expr {
	case ^ast.Selector_Expr:
		// This is a qualified type like mem.Arena
		if ident, ok := t.expr.derived_expr.(^ast.Ident); ok {
			ctx.target_selector = ident.name

			// Find the package path for this selector
			for imp in ctx.doc.imports {
				if imp.base == ident.name {
					ctx.target_package = imp.name
					ctx.target_import_spec = imp.original
					break
				}
			}
		}
	}
}

// Find cross-file usages of the alias (in other packages that import this one, or same package)
find_cross_file_usages :: proc(ctx: ^InlineAliasContext) {
	file_sources := workspace.get_files(context.temp_allocator)

	// The package name of the current file (where the alias is defined)
	current_pkg_name := filepath.base(ctx.doc.package_name)

	for source in file_sources {
		// Skip the current file
		if source.fullpath == ctx.doc.filepath {
			continue
		}

		doc, _ := documents.get_context(source.fullpath, ctx.config)

		// Check if this file is in the same package
		is_same_package := doc.ast.pkg_name == ctx.doc.ast.pkg_name

		usage := CrossFileUsage {
			fullpath         = source.fullpath,
			source           = source.text,
			selector_usages  = make([dynamic]^ast.Selector_Expr, context.temp_allocator),
			ident_usages     = make([dynamic]^ast.Ident, context.temp_allocator),
			file             = doc.ast,
			existing_imports = doc.imports,
			is_same_package  = is_same_package,
		}

		if is_same_package {
			// Same package - look for direct ident usages of AliasName
			find_ident_usages_in_stmts(doc.ast.decls[:], ctx.alias_name, &usage.ident_usages)

			if len(usage.ident_usages) > 0 {
				// Need to add import for target package since the alias will be replaced
				usage.needs_import = true
				usage.import_alias = ctx.target_selector

				// Check if target package is already imported
				for imp in doc.imports {
					if imp.name == ctx.target_package {
						usage.needs_import = false
						usage.import_alias = imp.base
						break
					}
				}

				append(&ctx.cross_file_usages, usage)
			}
		} else {
			// Different package - check if it imports our package
			imports_our_pkg := false
			pkg_alias := "" // The alias used to import our package (e.g., "test" or a custom alias)
			for imp in doc.imports {
				// Check if this import points to our package
				if strings.has_suffix(imp.name, current_pkg_name) || imp.name == ctx.doc.package_name {
					imports_our_pkg = true
					pkg_alias = imp.base
					break
				}
			}

			if !imports_our_pkg {
				continue
			}

			// Find selector expressions like pkg_alias.AliasName
			find_selector_usages_in_stmts(doc.ast.decls[:], pkg_alias, ctx.alias_name, &usage.selector_usages)

			if len(usage.selector_usages) > 0 {
				// Determine if we need to add an import for the target package
				usage.needs_import = true
				usage.import_alias = ctx.target_selector

				// Check if target package is already imported
				for imp in doc.imports {
					if imp.name == ctx.target_package {
						usage.needs_import = false
						usage.import_alias = imp.base
						break
					}
				}

				append(&ctx.cross_file_usages, usage)
			}
		}
	}
}

// Find selector expressions matching pkg.name pattern in statements
find_selector_usages_in_stmts :: proc(
	stmts: []^ast.Stmt,
	pkg_alias: string,
	symbol_name: string,
	usages: ^[dynamic]^ast.Selector_Expr,
) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}

		#partial switch s in stmt.derived_stmt {
		case ^ast.Value_Decl:
			// Check type annotation
			if s.type != nil {
				find_selector_usages_in_expr(s.type, pkg_alias, symbol_name, usages)
			}

			// Check in values
			for value in s.values {
				find_selector_usages_in_expr(value, pkg_alias, symbol_name, usages)

				if proc_lit, ok := value.derived_expr.(^ast.Proc_Lit); ok {
					if proc_lit.type != nil {
						find_selector_usages_in_expr(proc_lit.type, pkg_alias, symbol_name, usages)
					}
					if proc_lit.body != nil {
						if block, ok := proc_lit.body.derived_stmt.(^ast.Block_Stmt); ok {
							find_selector_usages_in_stmts(block.stmts[:], pkg_alias, symbol_name, usages)
						}
					}
				}
			}

		case ^ast.Block_Stmt:
			find_selector_usages_in_stmts(s.stmts[:], pkg_alias, symbol_name, usages)
		}
	}
}

// Find selector expressions matching pkg.name pattern in an expression
find_selector_usages_in_expr :: proc(
	expr: ^ast.Expr,
	pkg_alias: string,
	symbol_name: string,
	usages: ^[dynamic]^ast.Selector_Expr,
) {
	if expr == nil {
		return
	}

	#partial switch e in expr.derived_expr {
	case ^ast.Selector_Expr:
		// Check if this is pkg_alias.symbol_name
		if ident, ok := e.expr.derived_expr.(^ast.Ident); ok {
			if ident.name == pkg_alias {
				if field_ident, ok := e.field.derived_expr.(^ast.Ident); ok {
					if field_ident.name == symbol_name {
						append(usages, e)
					}
				}
			}
		}
		// Also recurse into the expression part
		find_selector_usages_in_expr(e.expr, pkg_alias, symbol_name, usages)

	case ^ast.Pointer_Type:
		find_selector_usages_in_expr(e.elem, pkg_alias, symbol_name, usages)

	case ^ast.Array_Type:
		find_selector_usages_in_expr(e.elem, pkg_alias, symbol_name, usages)

	case ^ast.Dynamic_Array_Type:
		find_selector_usages_in_expr(e.elem, pkg_alias, symbol_name, usages)

	case ^ast.Map_Type:
		find_selector_usages_in_expr(e.key, pkg_alias, symbol_name, usages)
		find_selector_usages_in_expr(e.value, pkg_alias, symbol_name, usages)

	case ^ast.Proc_Type:
		if e.params != nil {
			for param in e.params.list {
				find_selector_usages_in_expr(param.type, pkg_alias, symbol_name, usages)
			}
		}
		if e.results != nil {
			for result in e.results.list {
				find_selector_usages_in_expr(result.type, pkg_alias, symbol_name, usages)
			}
		}
	}
}

// Find direct ident usages of a symbol (for same-package cross-file)
find_ident_usages_in_stmts :: proc(stmts: []^ast.Stmt, symbol_name: string, usages: ^[dynamic]^ast.Ident) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}

		#partial switch s in stmt.derived_stmt {
		case ^ast.Value_Decl:
			// Skip declarations of the symbol itself (we don't want to replace the definition)
			for name in s.names {
				if ident, ok := name.derived_expr.(^ast.Ident); ok {
					if ident.name == symbol_name {
						// This is the declaration itself, skip this Value_Decl
						continue
					}
				}
			}

			// Check type annotation
			if s.type != nil {
				find_ident_usages_in_expr(s.type, symbol_name, usages)
			}

			// Check in values
			for value in s.values {
				find_ident_usages_in_expr(value, symbol_name, usages)

				if proc_lit, ok := value.derived_expr.(^ast.Proc_Lit); ok {
					if proc_lit.type != nil {
						find_ident_usages_in_expr(proc_lit.type, symbol_name, usages)
					}
					if proc_lit.body != nil {
						if block, ok := proc_lit.body.derived_stmt.(^ast.Block_Stmt); ok {
							find_ident_usages_in_stmts(block.stmts[:], symbol_name, usages)
						}
					}
				}
			}

		case ^ast.Block_Stmt:
			find_ident_usages_in_stmts(s.stmts[:], symbol_name, usages)
		}
	}
}

// Find direct ident usages of a symbol in an expression
find_ident_usages_in_expr :: proc(expr: ^ast.Expr, symbol_name: string, usages: ^[dynamic]^ast.Ident) {
	if expr == nil {
		return
	}

	#partial switch e in expr.derived_expr {
	case ^ast.Ident:
		if e.name == symbol_name {
			append(usages, e)
		}

	case ^ast.Selector_Expr:
		// Don't match pkg.symbol_name as a direct ident usage
		// Only recurse into sub-expressions
		find_ident_usages_in_expr(e.expr, symbol_name, usages)

	case ^ast.Pointer_Type:
		find_ident_usages_in_expr(e.elem, symbol_name, usages)

	case ^ast.Array_Type:
		find_ident_usages_in_expr(e.elem, symbol_name, usages)

	case ^ast.Dynamic_Array_Type:
		find_ident_usages_in_expr(e.elem, symbol_name, usages)

	case ^ast.Map_Type:
		find_ident_usages_in_expr(e.key, symbol_name, usages)
		find_ident_usages_in_expr(e.value, symbol_name, usages)

	case ^ast.Proc_Type:
		if e.params != nil {
			for param in e.params.list {
				find_ident_usages_in_expr(param.type, symbol_name, usages)
			}
		}
		if e.results != nil {
			for result in e.results.list {
				find_ident_usages_in_expr(result.type, symbol_name, usages)
			}
		}
	}
}

// Find all usages of an alias in the workspace
find_all_alias_usages_in_workspace :: proc(
	ctx: ^InlineAliasContext,
	alias_name: string,
	usages: ^[dynamic]^ast.Ident,
) {
	// Search in the current file's AST
	find_all_alias_usages_in_node(ctx.doc.ast.decls[:], alias_name, usages)
}

// Find all usages of an alias in AST nodes
find_all_alias_usages_in_node :: proc(stmts: []^ast.Stmt, alias_name: string, usages: ^[dynamic]^ast.Ident) {
	for stmt in stmts {
		if stmt == nil {
			continue
		}

		#partial switch s in stmt.derived_stmt {
		case ^ast.Value_Decl:
			// Check type annotation
			if s.type != nil {
				find_idents_in_expr(s.type, alias_name, usages)
			}

			// Check in values (procedure bodies, struct definitions, etc.)
			for value in s.values {
				if proc_lit, ok := value.derived_expr.(^ast.Proc_Lit); ok {
					// Check procedure signature
					if proc_lit.type != nil {
						find_idents_in_expr(proc_lit.type, alias_name, usages)
					}
					// Check procedure body
					if proc_lit.body != nil {
						if block, ok := proc_lit.body.derived_stmt.(^ast.Block_Stmt); ok {
							find_all_alias_usages_in_node(block.stmts[:], alias_name, usages)
						}
					}
				}

				// Check struct type fields
				if struct_type, ok := value.derived_expr.(^ast.Struct_Type); ok {
					if struct_type.fields != nil {
						for field in struct_type.fields.list {
							if field.type != nil {
								find_idents_in_expr(field.type, alias_name, usages)
							}
						}
					}
				}
			}

		case ^ast.Block_Stmt:
			find_all_alias_usages_in_node(s.stmts[:], alias_name, usages)

		case ^ast.If_Stmt:
			if s.body != nil {
				if block, ok := s.body.derived_stmt.(^ast.Block_Stmt); ok {
					find_all_alias_usages_in_node(block.stmts[:], alias_name, usages)
				}
			}
			if s.else_stmt != nil {
				if block, ok := s.else_stmt.derived_stmt.(^ast.Block_Stmt); ok {
					find_all_alias_usages_in_node(block.stmts[:], alias_name, usages)
				}
			}

		case ^ast.For_Stmt:
			if s.body != nil {
				if block, ok := s.body.derived_stmt.(^ast.Block_Stmt); ok {
					find_all_alias_usages_in_node(block.stmts[:], alias_name, usages)
				}
			}

		case ^ast.Switch_Stmt:
			if s.body != nil {
				if block, ok := s.body.derived_stmt.(^ast.Block_Stmt); ok {
					for stmt in block.stmts {
						if cc, ok := stmt.derived_stmt.(^ast.Case_Clause); ok {
							find_all_alias_usages_in_node(cc.body[:], alias_name, usages)
						}
					}
				}
			}
		}
	}
}

// Find identifiers with a specific name in an expression tree
find_idents_in_expr :: proc(expr: ^ast.Expr, name: string, usages: ^[dynamic]^ast.Ident) {
	if expr == nil {
		return
	}

	#partial switch e in expr.derived_expr {
	case ^ast.Ident:
		if e.name == name {
			append(usages, e)
		}

	case ^ast.Selector_Expr:
		find_idents_in_expr(e.expr, name, usages)

	case ^ast.Pointer_Type:
		find_idents_in_expr(e.elem, name, usages)

	case ^ast.Array_Type:
		find_idents_in_expr(e.len, name, usages)
		find_idents_in_expr(e.elem, name, usages)

	case ^ast.Dynamic_Array_Type:
		find_idents_in_expr(e.elem, name, usages)

	case ^ast.Multi_Pointer_Type:
		find_idents_in_expr(e.elem, name, usages)

	case ^ast.Map_Type:
		find_idents_in_expr(e.key, name, usages)
		find_idents_in_expr(e.value, name, usages)

	case ^ast.Proc_Type:
		if e.params != nil {
			for param in e.params.list {
				find_idents_in_expr(param.type, name, usages)
			}
		}
		if e.results != nil {
			for result in e.results.list {
				find_idents_in_expr(result.type, name, usages)
			}
		}

	case ^ast.Call_Expr:
		find_idents_in_expr(e.expr, name, usages)
		for arg in e.args {
			find_idents_in_expr(arg, name, usages)
		}
	}
}

// Find an identifier at position in type context
find_ident_at_position_in_type_context :: proc(decls: []^ast.Stmt, abs_pos: common.AbsolutePosition) -> ^ast.Ident {
	for decl in decls {
		if !position_in_node(decl, abs_pos) {
			continue
		}

		#partial switch d in decl.derived_stmt {
		case ^ast.Value_Decl:
			// Check in type annotations
			if d.type != nil {
				if ident := find_ident_at_position_in_expr(d.type, abs_pos); ident != nil {
					return ident
				}
			}

			// Check in procedure signatures and bodies
			for value in d.values {
				if proc_lit, ok := value.derived_expr.(^ast.Proc_Lit); ok {
					if proc_lit.type != nil {
						if ident := find_ident_at_position_in_expr(proc_lit.type, abs_pos); ident != nil {
							return ident
						}
					}
					// Check inside procedure body
					if proc_lit.body != nil {
						if ident := find_ident_in_block(proc_lit.body, abs_pos); ident != nil {
							return ident
						}
					}
				}
			}
		}
	}

	return nil
}

// Find an identifier in type context within a block statement
find_ident_in_block :: proc(stmt: ^ast.Stmt, abs_pos: common.AbsolutePosition) -> ^ast.Ident {
	if stmt == nil || !position_in_node(stmt, abs_pos) {
		return nil
	}

	#partial switch s in stmt.derived_stmt {
	case ^ast.Block_Stmt:
		for inner_stmt in s.stmts {
			if ident := find_ident_in_block(inner_stmt, abs_pos); ident != nil {
				return ident
			}
		}

	case ^ast.Value_Decl:
		// Check type annotation in variable declarations
		if s.type != nil {
			if ident := find_ident_at_position_in_expr(s.type, abs_pos); ident != nil {
				return ident
			}
		}

	case ^ast.If_Stmt:
		if s.body != nil {
			if ident := find_ident_in_block(s.body, abs_pos); ident != nil {
				return ident
			}
		}
		if s.else_stmt != nil {
			if ident := find_ident_in_block(s.else_stmt, abs_pos); ident != nil {
				return ident
			}
		}

	case ^ast.For_Stmt:
		if s.body != nil {
			if ident := find_ident_in_block(s.body, abs_pos); ident != nil {
				return ident
			}
		}

	case ^ast.Switch_Stmt:
		if s.body != nil {
			if block, ok := s.body.derived_stmt.(^ast.Block_Stmt); ok {
				for inner_stmt in block.stmts {
					if ident := find_ident_in_block(inner_stmt, abs_pos); ident != nil {
						return ident
					}
				}
			}
		}

	case ^ast.Case_Clause:
		for inner_stmt in s.body {
			if ident := find_ident_in_block(inner_stmt, abs_pos); ident != nil {
				return ident
			}
		}
	}

	return nil
}

// Find an identifier at position within an expression tree
find_ident_at_position_in_expr :: proc(expr: ^ast.Expr, abs_pos: common.AbsolutePosition) -> ^ast.Ident {
	if expr == nil || !position_in_node(expr, abs_pos) {
		return nil
	}

	#partial switch e in expr.derived_expr {
	case ^ast.Ident:
		return e

	case ^ast.Selector_Expr:
		// Check the selector part first (right side)
		if ident, ok := e.field.derived_expr.(^ast.Ident); ok {
			if position_in_node(ident, abs_pos) {
				return ident
			}
		}
		// Then check the expr part (left side)
		return find_ident_at_position_in_expr(e.expr, abs_pos)

	case ^ast.Pointer_Type:
		return find_ident_at_position_in_expr(e.elem, abs_pos)

	case ^ast.Array_Type:
		if ident := find_ident_at_position_in_expr(e.len, abs_pos); ident != nil {
			return ident
		}
		return find_ident_at_position_in_expr(e.elem, abs_pos)

	case ^ast.Dynamic_Array_Type:
		return find_ident_at_position_in_expr(e.elem, abs_pos)

	case ^ast.Multi_Pointer_Type:
		return find_ident_at_position_in_expr(e.elem, abs_pos)

	case ^ast.Map_Type:
		if ident := find_ident_at_position_in_expr(e.key, abs_pos); ident != nil {
			return ident
		}
		return find_ident_at_position_in_expr(e.value, abs_pos)

	case ^ast.Proc_Type:
		if e.params != nil {
			for param in e.params.list {
				if ident := find_ident_at_position_in_expr(param.type, abs_pos); ident != nil {
					return ident
				}
			}
		}
		if e.results != nil {
			for result in e.results.list {
				if ident := find_ident_at_position_in_expr(result.type, abs_pos); ident != nil {
					return ident
				}
			}
		}
	}

	return nil
}

// Find an alias declaration by name
find_alias_decl_by_name :: proc(
	decls: []^ast.Stmt,
	ast_context: ^AstContext,
	alias_name: string,
) -> (
	^ast.Value_Decl,
	^ast.Expr,
) {
	for decl in decls {
		#partial switch d in decl.derived_stmt {
		case ^ast.Value_Decl:
			// Check if this is a type alias
			if len(d.names) != 1 || len(d.values) != 1 || d.type != nil {
				continue
			}

			// Check if name matches
			if name, ok := d.names[0].derived_expr.(^ast.Ident); ok {
				if name.name == alias_name {
					return d, d.values[0]
				}
			}
		}
	}

	return nil, nil
}

// Generate the workspace edit for inlining the alias
generate_inline_alias_edit :: proc(ctx: ^InlineAliasContext, uri: common.FileUri) -> (WorkspaceEdit, bool) {
	edit := WorkspaceEdit {
		changes = make(map[common.FileUri][]TextEdit, context.temp_allocator),
	}

	source := string(ctx.doc.text)

	// Get the text representation of the target type
	target_type_text := get_expr_text(source, ctx.target_type)

	if ctx.target_usage != nil {
		// Single usage inline - only replace the usage under the cursor
		usage_range := common.get_token_range(ctx.target_usage, source)

		replacement_text := target_type_text

		// Check if we need to qualify with a package selector
		if ctx.target_package != "" {
			// Find what package alias is used at the usage site
			// For now, use the same selector as in the definition
			replacement_text = target_type_text
		}

		uri_edits := make([dynamic]TextEdit, context.temp_allocator)
		append(&uri_edits, TextEdit{range = usage_range, newText = replacement_text})

		edit.changes[uri] = uri_edits[:]
		return edit, true
	}

	// Full inline - replace all usages and remove the declaration
	uri_edits := make([dynamic]TextEdit, context.temp_allocator)

	// Remove the alias declaration - delete the entire line including the newline
	decl_range := common.get_token_range(ctx.alias_decl, source)

	// Start from the beginning of the line (character 0)
	decl_range.start.character = 0

	// Extend to include the newline at the end of the line
	src := ctx.doc.ast.src
	end_offset, _ := common.get_absolute_position(decl_range.end, transmute([]u8)source)
	if end_offset < len(src) && src[end_offset] == '\n' {
		// Move end position to the start of the next line
		decl_range.end.line += 1
		decl_range.end.character = 0
	}

	append(&uri_edits, TextEdit{range = decl_range, newText = ""})

	// Replace all usages in current file
	for usage in ctx.all_usages {
		usage_range := common.get_token_range(usage, source)
		replacement_text := target_type_text

		append(&uri_edits, TextEdit{range = usage_range, newText = replacement_text})
	}

	edit.changes[uri] = uri_edits[:]

	// Handle cross-file usages
	for &cross_usage in ctx.cross_file_usages {
		cross_edits := make([dynamic]TextEdit, context.temp_allocator)

		// Build the replacement type text for this file
		// Use the appropriate import alias
		cross_replacement := ""
		if ctx.target_selector != "" {
			// Get the type name from our target type (e.g., "Arena" from "mem.Arena")
			type_name := ""
			#partial switch t in ctx.target_type.derived_expr {
			case ^ast.Selector_Expr:
				if field_ident, ok := t.field.derived_expr.(^ast.Ident); ok {
					type_name = field_ident.name
				}
			case ^ast.Ident:
				type_name = t.name
			}

			if type_name != "" {
				cross_replacement = fmt.tprintf("%s.%s", cross_usage.import_alias, type_name)
			}
		}

		if cross_replacement == "" {
			cross_replacement = target_type_text
		}

		// Replace all selector usages (e.g., test.MyArena -> mem.Arena) for cross-package
		for selector in cross_usage.selector_usages {
			selector_range := common.get_token_range(selector, cross_usage.source)
			append(&cross_edits, TextEdit{range = selector_range, newText = cross_replacement})
		}

		// Replace all direct ident usages (for same-package cross-file)
		for ident in cross_usage.ident_usages {
			ident_range := common.get_token_range(ident, cross_usage.source)
			append(&cross_edits, TextEdit{range = ident_range, newText = cross_replacement})
		}

		// Handle import changes if needed
		if cross_usage.needs_import && ctx.target_import_spec != "" {
			if cross_usage.is_same_package {
				// For same-package, we need to ADD an import (not replace)
				// Find the position to insert the import
				// We want to insert BEFORE the first declaration (proc, type, etc.)
				// after the package declaration

				insert_line := 1 // Default: after package line

				// Find the first non-import declaration to insert before
				for decl in cross_usage.file.decls {
					// Skip import declarations - we want to insert after them
					if _, is_import := decl.derived_stmt.(^ast.Import_Decl); is_import {
						imp_range := common.get_token_range(decl, cross_usage.source)
						insert_line = imp_range.end.line + 1
						continue
					}

					// Found a non-import decl - insert before it
					decl_range := common.get_token_range(decl, cross_usage.source)
					insert_line = decl_range.start.line
					break
				}

				insert_pos := common.Position {
					line      = insert_line,
					character = 0,
				}

				// Insert the new import followed by a blank line
				new_import := fmt.tprintf("import %s\n\n", ctx.target_import_spec)
				import_range := common.Range {
					start = insert_pos,
					end   = insert_pos,
				}
				append(&cross_edits, TextEdit{range = import_range, newText = new_import})
			} else {
				// For cross-package, find and replace the import
				current_pkg_name := filepath.base(ctx.doc.package_name)
				for imp in cross_usage.existing_imports {
					if strings.has_suffix(imp.name, current_pkg_name) || imp.name == ctx.doc.package_name {
						// Found the import to replace
						if imp.import_decl != nil {
							import_range := common.get_token_range(imp.import_decl, cross_usage.source)
							// Remove entire line
							import_range.start.character = 0
							// Find end of line
							end_off, _ := common.get_absolute_position(
								import_range.end,
								transmute([]u8)cross_usage.source,
							)
							if end_off < len(cross_usage.source) && cross_usage.source[end_off] == '\n' {
								import_range.end.line += 1
								import_range.end.character = 0
							}
							// Replace with the new import
							new_import := fmt.tprintf("import %s\n", ctx.target_import_spec)
							append(&cross_edits, TextEdit{range = import_range, newText = new_import})
						}
						break
					}
				}
			}
		}

		if len(cross_edits) > 0 {
			uri := common.path_to_uri(cross_usage.fullpath)
			edit.changes[uri] = cross_edits[:]
		}
	}

	return edit, true
}

// Get the text representation of an expression from source code
get_expr_text :: proc(source: string, expr: ^ast.Expr) -> string {
	if expr == nil {
		return ""
	}

	start := int(expr.pos.offset)
	end := int(expr.end.offset)

	if start < 0 || end > len(source) || start > end {
		return ""
	}

	return source[start:end]
}

// Find the parent Call_Expr that contains this identifier
// Returns nil if the identifier is not inside a Call_Expr
find_parent_call_expr :: proc(decls: []^ast.Stmt, ident: ^ast.Ident) -> ^ast.Call_Expr {
	// TODO: Implement actual AST traversal to find parent Call_Expr
	return nil
}

// Extend a range to cover the full line (for removal)
extend_range_to_full_line :: proc(source: string, range: common.Range) -> common.Range {
	extended := range

	// Find the start of the line
	start_offset, _ := common.get_absolute_range(range, transmute([]u8)source)
	line_start := start_offset.start

	for line_start > 0 && source[line_start - 1] != '\n' {
		line_start -= 1
	}

	// Find the end of the line (including newline)
	line_end := start_offset.end
	for line_end < len(source) && source[line_end] != '\n' {
		line_end += 1
	}
	if line_end < len(source) {
		line_end += 1 // Include the newline
	}

	// Convert back to Position
	extended.start.line = range.start.line
	extended.start.character = 0
	extended.end.line = range.end.line + 1
	extended.end.character = 0

	return extended
}
