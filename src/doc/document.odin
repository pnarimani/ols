package doc

import "core:odin/ast"

import "src:common"

Package :: struct {
	name:          string, //the entire absolute path to the directory
	base:          string,
	base_original: string,
	original:      string,
	range:         common.Range,
	import_decl:   ^ast.Import_Decl,
}

ParserError :: struct {
	message: string,
	line:    int,
	column:  int,
	file:    string,
	offset:  int,
}

// Document represents an open document in the editor.
// Stores URI and raw text bytes in persistent memory.
Document :: struct {
	uri:  common.Uri,
	text: []u8,
}

// DocumentContext holds parsed data for a document.
DocumentContext :: struct {
	uri:          common.Uri,
	text:         []u8,
	ast:          ast.File,
	imports:      []Package,
	package_name: string,
	fullpath:     string,
	errors:       []ParserError,
}
