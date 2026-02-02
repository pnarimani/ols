package ols_testing

import "core:log"
import "core:strings"
import "core:testing"
import "src:server"

expect_hover :: proc(t: ^testing.T, src: ^Source, expect_hover_string: string) {
	setup(src)
	defer teardown(src)
	req_ctx := make_test_request_context(src)
	hover, valid, ok := server.get_hover_information(&req_ctx)

	if !ok {
		log.error(t, "Failed get_hover_information")
		return
	}

	if !valid {
		log.error(t, "Failed get_hover_information")
		return
	}

	first_strip, _ := strings.remove(hover.contents.value, "```odin\n", 2, context.temp_allocator)
	content_without_markdown, _ := strings.remove(first_strip, "\n```", 2, context.temp_allocator)

	if content_without_markdown != expect_hover_string {
		log.errorf("Expected hover string:\n%q, but received:\n%q", expect_hover_string, content_without_markdown)
	}
}
