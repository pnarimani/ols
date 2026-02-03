package ols_testing

import "core:log"
import "core:strings"
import "core:testing"
import "src:server"

expect_completion_labels :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	expect_labels: []string,
	expect_excluded: []string = nil,
) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	req_ctx := make_test_request_context(src)
	completion_list, ok := server.get_completion_list(&req_ctx, completion_context)

	if !ok {
		log.error("Failed get_completion_list")
	}

	if len(expect_labels) == 0 && len(completion_list.items) > 0 {
		log.errorf("Expected empty completion label, but received %v", completion_list.items)
	}

	flags := make([]int, len(expect_labels), context.temp_allocator)

	for expect_label, i in expect_labels {
		for completion, j in completion_list.items {
			if expect_label == completion.label {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected completion detail %v, but received %v", expect_labels[i], completion_list.items)
		}
	}

	for expect_exclude in expect_excluded {
		for completion in completion_list.items {
			if expect_exclude == completion.label {
				log.errorf("Expected completion label %v to not be included", expect_exclude)
			}
		}
	}
}

expect_completion_docs :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	expect_details: []string,
	expect_excluded: []string = nil,
) {
	setup(src)
	defer teardown(src)

	get_doc :: proc(doc: server.CompletionDocumention) -> string {
		switch v in doc {
		case string:
			return v
		case server.MarkupContent:
			first_strip, _ := strings.remove(v.value, "```odin\n", 2, context.temp_allocator)
			content_without_markdown, _ := strings.remove(first_strip, "\n```", 2, context.temp_allocator)
			return content_without_markdown
		}
		return ""
	}

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	req_ctx := make_test_request_context(src)
	completion_list, ok := server.get_completion_list(&req_ctx, completion_context)

	if !ok {
		log.error("Failed get_completion_list")
	}

	if len(expect_details) == 0 && len(completion_list.items) > 0 {
		log.errorf("Expected empty completion label, but received %v", completion_list.items)
	}

	flags := make([]int, len(expect_details), context.temp_allocator)

	for expect_detail, i in expect_details {
		for completion, j in completion_list.items {
			if expect_detail == get_doc(completion.documentation) {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected completion label: \n%v\nbut received \n%v", expect_details[i], completion_list.items)
		}
	}

	for expect_exclude in expect_excluded {
		for completion in completion_list.items {
			if expect_exclude == get_doc(completion.documentation) {
				log.errorf("Expected completion label: \n%v\nto not be included", expect_exclude)
			}
		}
	}
}

expect_completion_insert_text :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	expect_inserts: []string,
) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	req_ctx := make_test_request_context(src)
	completion_list, ok := server.get_completion_list(&req_ctx, completion_context)

	if !ok {
		log.error("Failed get_completion_list")
	}

	if len(expect_inserts) == 0 && len(completion_list.items) > 0 {
		log.errorf("Expected empty completion inserts, but received %v", completion_list.items)
	}

	flags := make([]int, len(expect_inserts), context.temp_allocator)

	for expect_insert, i in expect_inserts {
		for completion, j in completion_list.items {
			if insert_text, ok := completion.insertText.(string); ok {
				if expect_insert == insert_text {
					flags[i] += 1
					continue
				}
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected completion insert %v, but received %v", expect_inserts[i], completion_list.items)
		}
	}
}

expect_completion_edit_text :: proc(
	t: ^testing.T,
	src: ^Source,
	trigger_character: string,
	label: string,
	expected_text: string,
) {
	setup(src)
	defer teardown(src)

	completion_context := server.CompletionContext {
		triggerCharacter = trigger_character,
	}

	req_ctx := make_test_request_context(src)
	completion_list, ok := server.get_completion_list(&req_ctx, completion_context)

	if !ok {
		log.error("Failed get_completion_list")
	}

	found := false
	for completion in completion_list.items {
		if completion.label == label {
			found = true
			if text_edit, has_edit := completion.textEdit.(server.TextEdit); has_edit {
				if text_edit.newText != expected_text {
					log.errorf(
						"Completion '%v' expected textEdit.newText %q, but received %q",
						label,
						expected_text,
						text_edit.newText,
					)
				}
			} else {
				log.errorf("Completion '%v' has no textEdit", label)
			}
			break
		}
	}
	if !found {
		log.errorf("Expected completion label '%v' not found in %v", label, completion_list.items)
	}
}
