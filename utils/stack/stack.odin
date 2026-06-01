package stack

// version 11

import "core:fmt"
import "core:slice"


Stack :: struct($T: typeid) {
	_items: [dynamic]T,
}

destroy :: #force_inline proc(s: ^$T/Stack($V)) {
	empty(s)
	delete(s._items)
}

init :: proc(s: ^$T/Stack($V), allocator := context.allocator, loc := #caller_location) {
	s._items = make([dynamic]V, allocator, loc)
}

empty :: #force_inline proc(s: ^$T/Stack($V)) {
	clear(&s._items)
}

length :: #force_inline proc(s: ^$T/Stack($V)) -> int {
 	return len(s._items)
}

// is_empty :: #force_inline proc(s: ^$T/Stack($V)) -> bool {
//  	return len(s._items) == 0
// }

push_top :: #force_inline proc(s: ^$T/Stack($V), val: V) {
	append(&s._items, val)
}

pop_top :: #force_inline proc(s: ^$T/Stack($V), loc := #caller_location) -> V {
	assert(len(s._items) > 0, fmt.tprintf("%s:%d", loc.file_path, loc.line), loc=loc)
	return pop(&s._items)
}

peek_top :: #force_inline proc(s: ^$T/Stack($V), loc := #caller_location) -> V {
	assert(len(s._items) > 0, fmt.tprintf("%s:%d", loc.file_path, loc.line), loc=loc)
	return s._items[len(s._items)-1]
}
