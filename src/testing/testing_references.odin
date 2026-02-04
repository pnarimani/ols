package ols_testing

import "core:log"
import "core:testing"
import "src:common"
import "src:server"

expect_reference_locations :: proc(t: ^testing.T, src: ^Source) {
	setup(src)
	defer teardown(src)

	primary := get_primary_file(src)
	doc_ctx := get_file_doc_ctx(src, primary)
	locations, ok := server.get_references(&doc_ctx, primary.position)

	for expect_location in primary.encoded_locations {
		match := false
		for location in locations {
			if location.range == expect_location.range {
				match = true
			}
		}
		if !match {
			ok = false
			log.errorf("\nFailed to match with location: %v", expect_location)
		}
	}

	if !ok {
		log.error("\nReceived:\n")
		for location in locations {
			log.errorf("%v \n", location)
		}
	}
}
