package ols_testing

import "core:log"
import "core:testing"
import "src:server"

expect_signature_labels :: proc(t: ^testing.T, src: ^Source, expect_labels: []string) {
	setup(src)
	defer teardown(src)

	req_ctx := make_test_request_context(src)
	help, ok := server.get_signature_information(&req_ctx)

	if !ok {
		log.error("Failed get_signature_information")
	}

	if len(expect_labels) == 0 && len(help.signatures) > 0 {
		log.errorf("Expected empty signature label, but received %v", help.signatures)
	}

	flags := make([]int, len(expect_labels), context.temp_allocator)

	for expect_label, i in expect_labels {
		for signature, j in help.signatures {
			if expect_label == signature.label {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected signature label %v, but received %v", expect_labels[i], help.signatures)
		}
	}

}

expect_signature_parameter_position :: proc(t: ^testing.T, src: ^Source, position: int) {
	setup(src)
	defer teardown(src)

	req_ctx := make_test_request_context(src)
	help, ok := server.get_signature_information(&req_ctx)

	if help.activeParameter != position {
		log.errorf("expected parameter position %v, but received %v", position, help.activeParameter)
	}
}
