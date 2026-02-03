---
applyTo: '**'
---

# Odin Memory Allocator Rules

When reviewing or writing Odin code, enforce these allocator rules strictly:

## Quick Decision Guide
* Is the data returned? → Use allocator parameter
* Is the data stored in a struct with allocator field? → Use that struct's allocator
* Is the data temporary/internal only? → Use context.temp_allocator
* Is this a default parameter? → Must be context.allocator, never context.temp_allocator

## Parameter Rules
1. **Procs that allocate memory** must have `allocator := context.allocator` as the last parameter
2. **NEVER use** `allocator := context.temp_allocator` as a default parameter - this is forbidden

## Return Value Rules  
3. **Returned objects** and ALL their sub-objects must be **explicitly** allocated using the passed `allocator` parameter
4. **Never use implicit `context.allocator`** for returned data - always pass `allocator` explicitly to `make`/`new`/`strings.clone`/etc.
5. **Propagate allocator** to any called proc if that proc's result is being returned:
   ```odin
   // CORRECT: Explicit allocator for all returned data
   get_data :: proc(allocator := context.allocator) -> []string {
       result := make([]string, 10, allocator)  // Explicit - GOOD
       result[0] = strings.clone("hello", allocator)  // Explicit - GOOD
       return result
   }
   
   // WRONG: Using implicit context.allocator for returned data
   get_data_bad :: proc(allocator := context.allocator) -> []string {
       result := make([]string, 10)  // Implicit context.allocator - BAD
       return result
   }
   ```

## Internal Data Rules
6. Temporary working data that is NOT returned must use context.temp_allocator:
```odin
process :: proc(allocator := context.allocator) -> []Result {
    temp_buffer := make([dynamic]int, context.temp_allocator)  // NOT returned, use temp
    results := make([dynamic]Result, allocator)                 // IS returned, use allocator
    // ... process using temp_buffer, populate results ...
    return results[:]
}
```

## Data Structure Rules
7. **Structs with allocator fields**: All data stored in the struct must be allocated using that struct's allocator. **Explicitly pass** the struct's allocator to specific `make`/`new` calls - do NOT set `context.allocator = struct.allocator` as this risks unintended allocations:
```odin
// CORRECT: Explicitly pass struct's allocator only where needed
add_item :: proc(collection: ^Collection, name: string) {
    cloned_name := strings.clone(name, collection.allocator)  // Explicit
    item := new(Item, collection.allocator)                    // Explicit
    append(&collection.items, item)  // items already uses collection.allocator
}

// WRONG: Setting context.allocator globally is dangerous
add_item_bad :: proc(collection: ^Collection, name: string) {
    context.allocator = collection.allocator  // RISKY - affects ALL allocations
    // ...
}
```

# Odin Language Features

## Implicit `context`

Each scope has an implicit `context` variable, passed by pointer to procedure calls. When a scope ends, the parent's `context` is restored.

```odin
main :: proc() {
	{
		context.allocator = my_custom_allocator()
		supertramp() // receives modified context
	}
	// context.allocator restored to original
}

supertramp :: proc() {
	ptr := new(int) // uses my_custom_allocator from caller's context
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

1. **MAP ALLOCATORS PER SCOPE**
   - Document which `context.allocator` is active in each scope of the code
   - Trace the allocator through nested scopes and procedure calls
   - Note any explicit allocator overrides

2. **TRACE ALLOCATION-DEALLOCATION PAIRS**
   - For EVERY allocation (new, make, strings.clone, fmt.aprintf, etc.), identify which allocator was used
   - Verify deallocations use the SAME allocator
   - Flag any mismatches as the root cause before proposing fixes

## Extra Information
If you cannot understand odin syntax, look up https://odin-lang.org/docs/overview/
Documentation for odin packages can be found at https://pkg.odin-lang.org/

## Logging
If you need to log, you need to first import the logging package:
```odin
import "core:log"
```