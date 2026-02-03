package documents

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
// Stores path and raw text bytes in persistent memory.
DocumentData :: struct {
	filepath: string,
	text:     []u8,
}

// documents.Document holds parsed data for a document.
Document :: struct {
	text:         []u8,
	syntaxTree:   ast.File,
	imports:      []Package,
	package_name: string,
	filepath:     string,
	errors:       []ParserError,
}
