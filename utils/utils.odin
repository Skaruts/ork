package utils

import "core:strings"


to_cstr :: proc(str:string) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator)
}
