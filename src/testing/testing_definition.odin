package ols_testing

import "core:log"
import "core:testing"
import "src:common"
import "src:server"

expect_definition_locations :: proc(t: ^testing.T, src: ^Source, expect_locations: []common.Location) {
	setup(src)
	defer teardown(src)

	req_ctx := make_test_request_context(src)
	locations, ok := server.get_definition_location(&req_ctx)

	if !ok {
		log.error("Failed get_definition_location")
	}

	if len(expect_locations) == 0 && len(locations) > 0 {
		log.errorf("Expected empty locations, but received %v", locations)
	}

	flags := make([]int, len(expect_locations), context.temp_allocator)

	for expect_location, i in expect_locations {
		for location, j in locations {
			if location.range == expect_location.range {
				flags[i] += 1
			}
		}
	}

	for flag, i in flags {
		if flag != 1 {
			log.errorf("Expected location %v, but received %v", expect_locations[i].range, locations)
		}
	}
}
