---
applyTo: '**'
---

## Implicit `context`

In each scope, there is an implicit value named context. This context variable is local to each scope and is implicitly passed by pointer to any procedure call in that scope (if the procedure has the Odin calling convention).

When a scope ends, that scope's `context` is discarded and the parent scope's `context` is restored.

CRITICAL: Before analyzing or modifying code that involves memory operations, you MUST first document the `context.allocator` value for each scope in the code. Map out which allocator is active in each scope to ensure correct memory safety reasoning.

```odin
main :: proc() {
	context.user_index = 456
	{
		context.allocator = my_custom_allocator() // allocator change
		context.user_index = 123
		supertramp() // the `context` for this scope is implicitly passed to `supertramp`
	}
	// restored to outer scope's context

	assert(context.user_index == 456) 
}

supertramp :: proc() {
	assert(context.user_index == 123) 
	assert(context.allocator == my_custom_allocator())
	ptr := new(int) // allocated with my_custom_allocator
	free(ptr) // deallocated with my_custom_allocator
}
```

## Memory Safety
Odin is a manual memory management based language. 

Types might accept an allocator parameter to specify which allocator to use for memory allocation. If no allocator is specified, the `context.allocator` is used by default.
 
The following call:
```odin
ptr := new(int)
```
is equivalent to this:
```odin
ptr := new(int, context.allocator)
```

When the prompt involves memory issues, bugs, leaks, crashes, or allocation/deallocation problems, you MUST follow this protocol BEFORE proposing any fix:

1. **VERIFY ALLOCATOR UNDERSTANDING**
   - Repeat back how `context.allocator` works in Odin (implicit passing, scope-local behavior, restoration on scope exit)
   - Confirm that allocations and deallocations must use the SAME allocator

2. **MAP ALLOCATORS PER SCOPE**
   - Document which `context.allocator` is active in each scope of the code
   - Trace the allocator through nested scopes and procedure calls
   - Note any explicit allocator overrides (e.g., `context.allocator = context.temp_allocator`)

3. **TRACE ALLOCATION-DEALLOCATION PAIRS**
   - For EVERY allocation in the code (new, make, mem.alloc, etc.), identify:
	 * Which allocator was used (implicitly via context or explicitly passed)
	 * Where the corresponding deallocation occurs (free, delete, mem.free, etc.)
	 * Which allocator is active at the deallocation site
   - Create a table mapping each allocation to its deallocation with allocator info

4. **VERIFY ALLOCATOR MATCHING**
   - Confirm that each allocation/deallocation pair uses the same allocator
   - Flag any mismatches as the root cause before proposing fixes

This verification step is mandatory before proposing any fix or analysis.

## Extra Information
If you cannot understand odin syntax, look up https://odin-lang.org/docs/overview/
Documentation for odin packages can be found at https://pkg.odin-lang.org/

## Logging
If you need to log, you need to first import the logging package:
```odin
import "core:log"
```