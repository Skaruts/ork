package tracking_allocator

import "core:mem"
import "core:fmt"

/*
			Tracking Allocator  (Version 15)


	Usage:
		import track "tracking_alloc"

		main :: proc() {
			// do this before everything else
			when ODIN_DEBUG {
				context.allocator = track.init()
				defer track.finish()  //ensure this is always called last
			}

			// ...

			for running {    // main loop
				// ...

				// do this at the end of the loop (or defer it at the start of the loop)
				// (free the temp_allocator first)
				when ODIN_DEBUG { track.check_bad_frees() }
			}
		}
*/


@(private="file")
tracking_allocator : mem.Tracking_Allocator


init :: proc() -> mem.Allocator {
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	return mem.tracking_allocator(&tracking_allocator)
}

finish :: proc() {
	check_bad_frees()
	_report()
	_clear()
	mem.tracking_allocator_destroy(&tracking_allocator)
}

check_bad_frees :: proc() {
	if len(tracking_allocator.bad_free_array) > 0 {
		fmt.println("Found bad frees at:")
		for bf in tracking_allocator.bad_free_array {
			fmt.printf("  - %v\n", bf.location)
		}
		panic("There are bad frees!")
	}
}

_report :: proc() -> bool {
	leaked := len(tracking_allocator.allocation_map) > 0
	fmt.printf("\n----------------------------------------------\n")
	if leaked {
		fmt.printf("  Memory leaks: \n")

		for k, v in tracking_allocator.allocation_map {
			fmt.printf("    %v leaked %v bytes\n", v.location, v.size)
		}
	} else {
		fmt.printf("  No memory leaks.\n")
	}
	fmt.printf("----------------------------------------------\n\n")

	return leaked
}

_clear :: proc() {
	mem.tracking_allocator_clear(&tracking_allocator)
}


