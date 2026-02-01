---
applyTo: '**'
---

## Implicit `context`

In each scope, there is an implicit value named context. This context variable is local to each scope and is implicitly passed by pointer to any procedure call in that scope (if the procedure has the Odin calling convention).

When a scope ends, that scope's `context` is discarded and the parent scope's `context` is restored.

CRITICAL: Before analyzing or modifying code that involves memory operations, you MUST first document the `context.allocator` value for each scope in the code. Map out which allocator is active in each scope to ensure correct memory safety reasoning.

```odin
main :: proc() {
	c := context // copy the current scope's context

	context.user_index = 456
	{
		context.allocator = my_custom_allocator()
		context.user_index = 123
		supertramp() // the `context` for this scope is implicitly passed to `supertramp`
	}

	// `context` value is local to the scope it is in
	assert(context.user_index == 456)
}

supertramp :: proc() {
	c := context // this `context` is the same as the parent procedure that it was called from
	// From this example, context.user_index == 123
	// A context.allocator is assigned to the return value of `my_custom_allocator()`

	// The memory management procedure uses the `context.allocator` by default unless explicitly specified otherwise
	ptr := new(int)
	free(ptr)
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

IMPORTANT: It is CRITICAL that every allocation is deallocated with the SAME allocator that was used to allocate it. Mixing allocators will lead to undefined behavior and likely crashes.

## Extra Information
If you cannot understand odin syntax, look up https://odin-lang.org/docs/overview/
Documentation for odin packages can be found at https://pkg.odin-lang.org/

## Logging
If you need to log, you need to first import the logging package:
```odin
import "core:log"
```