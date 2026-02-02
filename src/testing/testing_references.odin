package ols_testing

import "core:log"
import "core:testing"
import "src:common"
import "src:server"

expect_reference_locations :: proc(
	t: ^testing.T,
	src: ^Source,
	expect_locations: []common.Location,
	expect_excluded: []common.Location = nil,
) {
	setup(src)
	defer teardown(src)

	locations, ok := server.get_references(src.doc_ctx, src.position)

	for expect_location in expect_locations {
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

	for expect_exclude in expect_excluded {
		for location in locations {
			if expect_exclude.range == location.range {
				log.errorf("Expected location %v to not be included\n", expect_exclude)
			}
		}
	}
}
