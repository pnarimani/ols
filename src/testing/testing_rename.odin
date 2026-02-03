package ols_testing

import "core:log"
import "core:testing"
import "src:common"
import "src:server"

expect_prepare_rename_range :: proc(t: ^testing.T, src: ^Source, expect_range: common.Range) {
	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	range, ok := server.get_prepare_rename(&primary.doc_ctx, primary.position)
	if !ok {
		log.error("Failed to find range")
	}

	if range != expect_range {
		ok = false
		log.errorf("Failed to match with range: %v", expect_range)
	}

	if !ok {
		log.error("Received: %v\n", range)
	}
}
