package doc

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
	documents: map[string]Document,
}

@(private = "file")
storage: DocumentStorage

// Initialize document storage with a persistent allocator.
// Must be called before any document operations.
init :: proc() {
	storage.allocator = context.allocator
	storage.documents = make(map[string]Document, storage.allocator)
}

shutdown :: proc() {
	for k, v in storage.documents {
		delete(v.text, storage.allocator)
		common.delete_uri(v.uri, storage.allocator)
		delete(k, storage.allocator)
	}

	delete(storage.documents)
}

// Get a document by URI string. Returns pointer to stored document, or nil if not found.
// Will attempt to load from disk if document is not in storage.
get :: proc(uri_string: string) -> ^Document {
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return nil
	}

	if document, ok := &storage.documents[uri.path]; ok {
		return document
	}

	return load_from_disk(uri)
}

// Load a document from disk and store it in storage.
// Returns pointer to the stored document, or nil on failure.
load_from_disk :: proc(uri: common.Uri) -> ^Document {
	fullpath := get_fullpath_from_uri(uri.path, context.temp_allocator)

	data, read_ok := os.read_entire_file(fullpath, context.temp_allocator)
	if !read_ok {
		log.errorf("Failed to read file from disk: %v", uri.path)
		return nil
	}

	doc, _ := open(uri, string(data))
	return doc
}

// Open a document with transferred text from the client.
// Returns pointer to the stored document and error status.
open :: proc {
	open_from_uri_string,
	open_from_uri,
}

open_from_uri_string :: proc(uri_string: string, text: string) -> (^Document, common.Error) {
	// Parse URI with temp allocator first, then clone to persistent storage
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		log.error("Failed to parse uri")
		return nil, .ParseError
	}

	return open_from_uri(uri, text)
}

open_from_uri :: proc(uri: common.Uri, text: string) -> (^Document, common.Error) {
	if document, ok := &storage.documents[uri.path]; ok {
		// Document already exists, update it
		// Free old data with persistent allocator
		common.delete_uri(document.uri, storage.allocator)
		delete(document.text, storage.allocator)

		// Clone new data to persistent storage
		document.uri = common.clone_uri(uri, storage.allocator)
		document.text = transmute([]u8)strings.clone(text, storage.allocator)
		return document, .None
	}

	// New document - clone data to persistent storage
	document := Document {
		uri  = common.clone_uri(uri, storage.allocator),
		text = transmute([]u8)strings.clone(text, storage.allocator),
	}

	key := strings.clone(uri.path, storage.allocator)
	storage.documents[key] = document

	return &storage.documents[key], .None
}

// Apply incremental changes to a document.
apply_changes :: proc(
	uri_string: string,
	changes: []ContentChangeEvent,
	version: Maybe(int) = nil,
) -> common.Error {
	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &storage.documents[uri.path]

	if document == nil {
		log.errorf("Client called change on an document not opened: %v ", uri.path)
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
close :: proc(uri_string: string) -> common.Error {
	log.infof("document close: %v", uri_string)

	uri, parsed_ok := common.parse_uri(uri_string, context.temp_allocator)

	if !parsed_ok {
		return .ParseError
	}

	document := &storage.documents[uri.path]

	if document == nil {
		log.errorf("Client called close on a document that was never opened: %v ", uri.path)
		return .InvalidRequest
	}

	common.delete_uri(document.uri, storage.allocator)
	delete(document.text, storage.allocator)

	// The key in the map was cloned with persistent allocator, need to free it
	for k, _ in storage.documents {
		if k == uri.path {
			delete(k, storage.allocator)
			break
		}
	}
	delete_key(&storage.documents, uri.path)

	return .None
}
