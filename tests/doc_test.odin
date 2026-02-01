package tests

import "core:log"
import "core:testing"

import "src:common"
import doc "src:documents"

@(test)
doc_apply_changes_full_replace :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a document
	original := "hello world"
	document, err := doc.open("file:///test/test.odin", original)
	testing.expect(t, err == .None, "open should succeed")
	testing.expect(t, document != nil, "document should not be nil")
	testing.expect_value(t, string(document.text), original)

	// Full replace (no range specified)
	new_text := "goodbye world"
	changes := []doc.ContentChangeEvent{
		{range = nil, text = new_text},
	}
	err = doc.apply_changes("file:///test/test.odin", changes)
	testing.expect(t, err == .None, "apply_changes should succeed")

	// Verify the document was updated
	updated := doc.get("file:///test/test.odin")
	testing.expect(t, updated != nil, "document should still exist")
	testing.expect_value(t, string(updated.text), new_text)
}

@(test)
doc_apply_changes_insert_at_beginning :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a document
	original := "world"
	document, _ := doc.open("file:///test/test.odin", original)
	testing.expect(t, document != nil, "document should not be nil")

	// Insert "hello " at the beginning
	changes := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 0, character = 0},
				end = {line = 0, character = 0},
			},
			text = "hello ",
		},
	}
	err := doc.apply_changes("file:///test/test.odin", changes)
	testing.expect(t, err == .None, "apply_changes should succeed")

	updated := doc.get("file:///test/test.odin")
	testing.expect_value(t, string(updated.text), "hello world")
}

@(test)
doc_apply_changes_insert_at_end :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a document
	original := "hello"
	document, _ := doc.open("file:///test/test.odin", original)
	testing.expect(t, document != nil, "document should not be nil")

	// Insert " world" at the end
	changes := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 0, character = 5},
				end = {line = 0, character = 5},
			},
			text = " world",
		},
	}
	err := doc.apply_changes("file:///test/test.odin", changes)
	testing.expect(t, err == .None, "apply_changes should succeed")

	updated := doc.get("file:///test/test.odin")
	testing.expect_value(t, string(updated.text), "hello world")
}

@(test)
doc_apply_changes_replace_middle :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a document
	original := "hello world"
	document, _ := doc.open("file:///test/test.odin", original)
	testing.expect(t, document != nil, "document should not be nil")

	// Replace "world" with "odin"
	changes := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 0, character = 6},
				end = {line = 0, character = 11},
			},
			text = "odin",
		},
	}
	err := doc.apply_changes("file:///test/test.odin", changes)
	testing.expect(t, err == .None, "apply_changes should succeed")

	updated := doc.get("file:///test/test.odin")
	testing.expect_value(t, string(updated.text), "hello odin")
}

@(test)
doc_apply_changes_delete :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a document
	original := "hello world"
	document, _ := doc.open("file:///test/test.odin", original)
	testing.expect(t, document != nil, "document should not be nil")

	// Delete " world"
	changes := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 0, character = 5},
				end = {line = 0, character = 11},
			},
			text = "",
		},
	}
	err := doc.apply_changes("file:///test/test.odin", changes)
	testing.expect(t, err == .None, "apply_changes should succeed")

	updated := doc.get("file:///test/test.odin")
	testing.expect_value(t, string(updated.text), "hello")
}

@(test)
doc_apply_changes_multiline :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a multiline document
	original := "line1\nline2\nline3"
	document, _ := doc.open("file:///test/test.odin", original)
	testing.expect(t, document != nil, "document should not be nil")

	// Replace "line2" with "replaced"
	changes := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 1, character = 0},
				end = {line = 1, character = 5},
			},
			text = "replaced",
		},
	}
	err := doc.apply_changes("file:///test/test.odin", changes)
	testing.expect(t, err == .None, "apply_changes should succeed")

	updated := doc.get("file:///test/test.odin")
	testing.expect_value(t, string(updated.text), "line1\nreplaced\nline3")
}

@(test)
doc_apply_changes_multiline_span :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a multiline document
	original := "line1\nline2\nline3"
	document, _ := doc.open("file:///test/test.odin", original)
	testing.expect(t, document != nil, "document should not be nil")

	// Replace from middle of line1 to middle of line3
	changes := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 0, character = 3},
				end = {line = 2, character = 3},
			},
			text = "X",
		},
	}
	err := doc.apply_changes("file:///test/test.odin", changes)
	testing.expect(t, err == .None, "apply_changes should succeed")

	updated := doc.get("file:///test/test.odin")
	testing.expect_value(t, string(updated.text), "linXe3")
}

@(test)
doc_apply_changes_multiple_sequential :: proc(t: ^testing.T) {
	doc.init()
	defer doc.shutdown()

	// Open a document
	original := "abc"
	document, _ := doc.open("file:///test/test.odin", original)
	testing.expect(t, document != nil, "document should not be nil")

	// Apply multiple changes in sequence (like typing)
	// Note: Each change should be applied based on current state
	changes1 := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 0, character = 3},
				end = {line = 0, character = 3},
			},
			text = "d",
		},
	}
	doc.apply_changes("file:///test/test.odin", changes1)

	changes2 := []doc.ContentChangeEvent{
		{
			range = common.Range{
				start = {line = 0, character = 4},
				end = {line = 0, character = 4},
			},
			text = "e",
		},
	}
	doc.apply_changes("file:///test/test.odin", changes2)

	updated := doc.get("file:///test/test.odin")
	testing.expect_value(t, string(updated.text), "abcde")
}