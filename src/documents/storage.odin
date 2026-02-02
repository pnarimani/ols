package documents

import "src:workspace"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"

import "src:common"

// ContentChangeEvent represents a change to a document's content.
// This mirrors the LSP TextDocumentContentChangeEvent type.
ContentChangeEvent :: struct {
	range: union {
		common.Range,
	},
	text:  string,
}

DocumentStorage :: struct {
	allocator: mem.Allocator,
	documents: map[string]DocumentData,
}

@(private = "file")
storage: DocumentStorage

// Initialize document storage with a persistent allocator.
// Must be called before any document operations.
init :: proc() {
	storage.allocator = context.allocator
	storage.documents = make(map[string]DocumentData, storage.allocator)
}

shutdown :: proc() {
	for k, v in storage.documents {
		delete(v.text, storage.allocator)
		delete(v.path, storage.allocator)
		delete(k, storage.allocator)
	}

	delete(storage.documents)
}

// Get a document by encoded path string. Returns pointer to stored document, or nil if not found.
// Will attempt to load from disk if document is not in storage.
get :: proc(encoded_path: string) -> ^DocumentData {
	path, parsed_ok := common.make_path(encoded_path, context.temp_allocator)

	if !parsed_ok {
		return nil
	}

	if document, ok := &storage.documents[path]; ok {
		return document
	}

	return load_from_disk(path)
}

// Load a document from disk and store it in storage.
// Returns pointer to the stored document, or nil on failure.
load_from_disk :: proc(path: string) -> ^DocumentData {
	fullpath := get_fullpath_from_path(path, context.temp_allocator)

	data, read_ok := workspace.read_file_content(fullpath, context.temp_allocator)
	if !read_ok {
		log.errorf("Failed to read file from disk: %v", path)
		return nil
	}

	doc, _ := open(path, string(data))
	return doc
}

// Open a document with transferred text from the client.
// Returns pointer to the stored document and error status.
open :: proc(path_or_encoded: string, text: string) -> (^DocumentData, common.Error) {
	// Try to parse as encoded path first
	path, parsed_ok := common.make_path(path_or_encoded, context.temp_allocator)
	if !parsed_ok {
		// If parsing fails, assume it's already a plain path
		path = path_or_encoded
	}

	if document, ok := &storage.documents[path]; ok {
		// Document already exists, update it
		// Free old data with persistent allocator
		delete(document.path, storage.allocator)
		delete(document.text, storage.allocator)

		// Clone new data to persistent storage
		document.path = strings.clone(path, storage.allocator)
		document.text = transmute([]u8)strings.clone(text, storage.allocator)
		return document, .None
	}

	// New document - clone data to persistent storage
	document := DocumentData {
		path = strings.clone(path, storage.allocator),
		text = transmute([]u8)strings.clone(text, storage.allocator),
	}

	key := strings.clone(path, storage.allocator)
	storage.documents[key] = document

	return &storage.documents[key], .None
}

// Apply incremental changes to a document.
apply_changes :: proc(
	encoded_path: string,
	changes: []ContentChangeEvent,
	version: Maybe(int) = nil,
) -> common.Error {
	path, parsed_ok := common.make_path(encoded_path, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &storage.documents[path]

	if document == nil {
		log.errorf("Client called change on an document not opened: %v ", path)
		return .InvalidRequest
	}

	for change in changes {
		//for some reason sublime doesn't seem to care even if i tell it to do incremental sync
		if range, ok := change.range.(common.Range); ok {
			absolute_range, ok := common.get_absolute_range(range, document.text)

			if !ok {
				return .ParseError
			}

			//lower bound is before the change
			lower := document.text[:absolute_range.start]

			//new change between lower and upper
			middle := change.text

			//upper bound is after the change
			upper := document.text[absolute_range.end:]

			//total new size needed
			new_size := len(lower) + len(change.text) + len(upper)

			new_text := make([]u8, new_size, storage.allocator)

			//join the 3 splices into the text
			copy(new_text, lower)
			copy(new_text[len(lower):], middle)
			copy(new_text[len(lower) + len(middle):], upper)

			delete(document.text, storage.allocator)

			document.text = new_text
		} else {
			new_text := make([]u8, len(change.text), storage.allocator)
			copy(new_text, change.text)
			delete(document.text, storage.allocator)
			document.text = new_text
		}
	}

	return .None
}

// Close a document and free its resources.
close :: proc(encoded_path: string) -> common.Error {
	log.infof("document close: %v", encoded_path)

	path, parsed_ok := common.make_path(encoded_path, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &storage.documents[path]

	if document == nil {
		log.errorf("Client called close on a document that was never opened: %v ", path)
		return .InvalidRequest
	}

	delete(document.path, storage.allocator)
	delete(document.text, storage.allocator)

	// The key in the map was cloned with persistent allocator, need to free it
	for k, _ in storage.documents {
		if k == path {
			delete(k, storage.allocator)
			break
		}
	}
	delete_key(&storage.documents, path)

	return .None
}
