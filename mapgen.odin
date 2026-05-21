/*

	NOTE: This map generation is currently very simple, and not really
	recommended for serious usage. For now it's intended as just a quick
	and dirty way to get a project started, with easy-to-create maps to
	test things out and move around in.

	This code may also change drastically in the future.

	My long-term goal is to explore the possibility of creating actually
	useful map generation tools, but for now this is not it.

*/
package ork


import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:math/rand"



// A field of cells used in the map generation process.
GenField :: []int


// A Map Generator.
MapGen :: struct {
	arena     : virtual.Arena,
	allocator : mem.Allocator,
	w         : int,
	h         : int,
	floor_id  : int,
	wall_id   : int,
	// rng       : runtime.Random_Generator,
	cells     : GenField,
	barriers  : GenField,
	rooms     : [dynamic]Rect,
}

// Creates a new Map Generator. The generated map will have `w, h` size.
// Use `floor_id` and `wall_id` if you need custom ids (this is usually
// only needed if you need to mix different generators).
new_mapgen :: proc(#any_int w, h: int, floor_id := 0, wall_id := 1) -> ^MapGen {
	mgen := _create_mapgen(w, h, floor_id, wall_id)
	append(&internal.map_gens, mgen)
	return mgen
}

// Destroys a Map Generator and frees its memory.
delete_mapgen :: proc(mgen: ^MapGen, loc := #caller_location) {
	if mgen == nil do return
	idx, ok := _get_item_index(internal.map_gens[:], mgen)
	if ok do unordered_remove(&internal.map_gens, idx)

	free_all(mgen.allocator)
	virtual.arena_destroy(&mgen.arena)
	free(mgen)
}



@private _create_mapgen :: proc(#any_int w, h: int, floor_id := 0, wall_id := 1) -> ^MapGen {
	mgen := new(MapGen)
	mgen.allocator = virtual.arena_allocator(&mgen.arena)

	mgen.w = w
	mgen.h = h
	mgen.floor_id = floor_id
	mgen.wall_id  = wall_id

	mgen.cells    = mapgen_create_field(w*h, wall_id, mgen.allocator)
	mgen.barriers = mapgen_create_field(w*h, wall_id, mgen.allocator)

	mgen.rooms = make([dynamic]Rect, 0, 0, mgen.allocator)

	return mgen
}


mapgen_create_field :: proc(#any_int length: int, def_value: $T, allocator: mem.Allocator) -> GenField {
	field := make(GenField, length, allocator)
	slice.fill(field, def_value)
	return field
}


mapgen_copy_field :: proc(dest: ^GenField, source: GenField) {
	for i in 0 ..< len(source) {
		dest[i] = source[i]
	}
}


// function MapGenerator:set_seed(seed)
//  mgen.rng:set_seed(seed)
// }


// Fills an area of the map with floors. `chance` (percentage 0..1) controls the density with which floors will be created.
mapgen_carve_area :: proc(mgen: ^MapGen, x, y, w, h: int, chance := 1.0, loc := #caller_location) {
	mapgen_fill_area(mgen, x, y, w, h, 1-chance, loc)
}

// Fills an area of the map with walls. `chance` (percentage 0..1) controls the density with which walls will be created.
mapgen_fill_area :: proc(mgen: ^MapGen, x, y, w, h: int, chance := 1.0, loc := #caller_location) {
	context.random_generator = internal.rng

	if x >= mgen.w-1 || y >= mgen.h-1 {
		fmt.panicf("position is outside map (%d, %d | %d, %d)", x, y, mgen.w, mgen.h, loc=loc)
	}
	if w <= 0 || h <= 0 {
		fmt.panicf("size is zero (w: %s, h: %s)", w, h, loc=loc)
	}

	l := max(x,   0     )
	r := min(x+w, mgen.w)
	t := max(y,   0     )
	b := min(y+h, mgen.h)

	for j in t ..< b {
		for i in l ..< r {
			if chance == 1 || rand.float64() < chance {
				mgen.cells[i+j*mgen.w] = mgen.floor_id
			} else {
				mgen.cells[i+j*mgen.w] = mgen.wall_id
			}
		}
	}
}


mapgen_make_rooms_random :: proc(mgen: ^MapGen, #any_int max_rooms, min_size, max_size: int) {
	context.random_generator = internal.rng

	clear(&mgen.rooms)
	max_tries := 3
	attempts := 0
	k := 1

	for k <= max_rooms || attempts > max_tries {
		attempts += 1
	// for _=0, max_rooms-1 do
		w := rand.int_max(max_size-1)       + min_size  // .rng:random(min_size, max_size)
		h := rand.int_max(max_size-1)       + min_size  // .rng:random(min_size, max_size)
		x := rand.int_max((mgen.w - w) - 2) + 1  // .rng:random(1, (mgen.w - w) - 1)
		y := rand.int_max((mgen.h - h) - 2) + 1  // .rng:random(1, (mgen.h - h) - 1)

		new_room := Rect{x, y, w, h}
		intersects := false

		for i in 0 ..< len(mgen.rooms) {
			if rect_intersects(new_room, mgen.rooms[i]) \
			|| rect_touches(new_room, mgen.rooms[i]) {
				intersects = true
				break
			}
		}

		if !intersects {
			k += 1
			attempts = 0
			append(&mgen.rooms, new_room)
			mapgen_carve_room(mgen, new_room)
		}
	}
}


mapgen_carve_room :: proc(mgen: ^MapGen, room: Rect) {
	for j in 0 ..< room.h {
		for i in 0 ..< room.w {
			x := room.x + i
			y := room.y + j
			mgen.cells[x+y*mgen.w] = mgen.floor_id
		}
	}
}


mapgen_carve_all_rooms :: proc(mgen: ^MapGen) {
	for i in 0 ..< len(mgen.rooms) {
		mapgen_carve_room(mgen, mgen.rooms[i])
	}
}


mapgen_connect_rooms_naive :: proc(mgen: ^MapGen) {
	for i in 1 ..< len(mgen.rooms) {
		last_idx := i-1 >= 0 ? i-1 : len(mgen.rooms)-1
		room1 := mgen.rooms[last_idx]
		room2 := mgen.rooms[i]
		if ! rect_touches(room1, room2) {
			from := mapgen_get_random_position_in_room(room1)
			to := mapgen_get_random_position_in_room(room2)

			// TODO: have this randomly choose a side
			// local mid = Vec2(to.x, from.y)
			mid := Vec2{from.x, to.y}

			l1 := line_points(from.x, from.y, mid.x, mid.y)
			l2 := line_points(mid.x, mid.y, to.x, to.y)

			mapgen_carve_points(mgen, l1)
			mapgen_carve_points(mgen, l2)
		}
	}
}


mapgen_carve_points :: proc(mgen: ^MapGen, points: [dynamic]Vec2, floor_id: Maybe(int) = nil) {
	_floor_id := mgen.floor_id
	if id, ok := floor_id.?; ok do _floor_id = id

	for i in 0..< len(points) {
		p := points[i]
		mgen.cells[p.x+p.y*mgen.w] = _floor_id
	}
}

mapgen_get_random_position_in_room :: proc(r: Rect) -> Vec2 {
	context.random_generator = internal.rng
	x := rand.int_max(r.w-2) + r.x+1
	y := rand.int_max(r.h-2) + r.y+1
	return Vec2{x, y}
}


mapgen_get_room_center :: proc(room: Rect) -> Vec2 {
	return Vec2{
		(room.x + room.x+room.w) / 2,
		(room.y + room.y+room.h) / 2
	}
}

mapgen_get_position_in_room :: proc(mgen: ^MapGen) -> (Vec2, int) {
	context.random_generator = internal.rng
	if len(mgen.rooms) == 0 {
		__warning("MapGenerator: no rooms to put player in")
		return {}, -1
	}
	room_idx := rand.int_max(len(mgen.rooms)-1) + 1
	return mapgen_get_room_center(mgen.rooms[room_idx]), room_idx
}

mapgen_get_random_position_in_map :: proc(mgen: ^MapGen) -> Vec2 {
	context.random_generator = internal.rng
	x := rand.int_max(mgen.w-1) + 1
	y := rand.int_max(mgen.h-1) + 1
	return Vec2{x, y}
}

mapgen_get_random_position_attempts :: proc(mgen: ^MapGen, attempts: int = 10000) -> Vec2 {
	// TODO: if the map is full, this will fail
	//       maybe use a dijkstra map or something to test if full?

	attempts := attempts
	for attempts > 0 {
		p := mapgen_get_random_position_in_map(mgen)
		if mgen.cells[p.x+p.y*mgen.w] == mgen.floor_id {
			return p
		}
		attempts -= 1
	}

	__warning("MagGenerator: couldn't find a suitable position for the player")
	return {}
}


mapgen_smooth_cells :: proc(mgen: ^MapGen, birth_rule, death_rule, smooth_steps: int) {
	new_field := mapgen_create_field(mgen.w*mgen.h, 0, context.temp_allocator)

	for _ in 0 ..< smooth_steps {
		mapgen_copy_field(&new_field, mgen.cells)

		for j in 1 ..< mgen.h-1 {
			for i in 1 ..< mgen.w-1 {
				idx := i+j*mgen.w
				nbs := mapgen_count_neighbors(mgen, i, j, mgen.wall_id, mgen.cells, true)
				old_id := mgen.cells[idx]  // old cell

				// if cell alive with not enough neighbors, KILL!
				if old_id == mgen.wall_id {
					if nbs < death_rule {
						new_field[idx] = mgen.floor_id
					} else {
						new_field[idx] = mgen.wall_id
					}

				// if cell dead with enough neighbors, revive it
				} else {
					if nbs > birth_rule {
						new_field[idx] = mgen.wall_id
					} else {
						new_field[idx] = mgen.floor_id
					}
				}
			}
		}
		mapgen_copy_field(&mgen.cells, new_field)
	}
}


mapgen_create_random_barriers :: proc(mgen: ^MapGen) {
	// TODO
}


mapgen_count_neighbors :: proc(mgen: ^MapGen, x, y, id: int, field: GenField, diagonals: bool) -> int {
	num_nbs: int

	l := x-1
	r := x+1
	u := y-1
	d := y+1

	if field[l+y*mgen.w] == id do num_nbs += 1
	if field[r+y*mgen.w] == id do num_nbs += 1
	if field[x+u*mgen.w] == id do num_nbs += 1
	if field[x+d*mgen.w] == id do num_nbs += 1

	if diagonals {
		if field[l+u*mgen.w] == id do num_nbs += 1
		if field[r+u*mgen.w] == id do num_nbs += 1
		if field[l+d*mgen.w] == id do num_nbs += 1
		if field[r+d*mgen.w] == id do num_nbs += 1
	}

	return num_nbs
}


mapgen_get_neighbor_mask :: proc(mgen: ^MapGen, x, y, id: int,
								 field: GenField) -> DirectionSet {
	// 128   1   16
	//   8        2
	//  64   4   32

	mask: DirectionSet
	l, r, u, d := x-1, x+1, y-1, y+1

	if field[x+u*mgen.w] == id do mask |= {.North}
	if field[r+y*mgen.w] == id do mask |= {.East}
	if field[x+d*mgen.w] == id do mask |= {.South}
	if field[l+y*mgen.w] == id do mask |= {.West}

	if field[r+u*mgen.w] == id do mask |= {.North_East}
	if field[r+d*mgen.w] == id do mask |= {.South_East}
	if field[l+d*mgen.w] == id do mask |= {.South_West}
	if field[l+u*mgen.w] == id do mask |= {.North_West}

	return mask
}


mapgen_remove_spikes :: proc(mgen: ^MapGen) {
	// TODO:  this could still be improved

	// remove spikes
	/*
		. . . . .       . . . . .        # # # # #
		. . . . .       . . # . .        . # . # .
		. . # . .       . . # . .        . . # . .
		# # # # #       # # # # #        # # # # #
	*/

	SPIKE_N :: DirectionSet {.South, .South_East, .South_West}
	SPIKE_S :: DirectionSet {.North, .North_East, .North_West}
	SPIKE_E :: DirectionSet {.West,  .North_West, .South_West}
	SPIKE_W :: DirectionSet {.East,  .North_East, .South_East}

	num_artifacts := 0

	for {
		num_artifacts = 0
		for j in 1 ..< mgen.h-1 {
			for i in 1 ..< mgen.w-1 {
				idx := i+j*mgen.w
				cell_id := mgen.cells[idx]

				mask := mapgen_get_neighbor_mask(mgen, i, j, cell_id, mgen.cells)
				n := mapgen_count_neighbors(mgen, i, j, cell_id, mgen.cells, true)

				if n <= 2                                 \
				|| (mask == SPIKE_N) || (mask == SPIKE_S) \
				|| (mask == SPIKE_W) || (mask == SPIKE_E)
				{
					num_artifacts += 1
					mgen.cells[idx] = cell_id == mgen.wall_id  \
									? mgen.floor_id                    \
									: mgen.wall_id
				}
			}
		}

		if num_artifacts == 0 do break
	}
}


mapgen_make_drunk_walk :: proc(gen: ^MapGen, start_pos: Vec2, steps: int, dir_chance := 1.0) -> Vec2 {
	context.random_generator = internal.rng

	dir_chance := clamp(dir_chance, 0, 1)

	gen.cells[start_pos.x+start_pos.y*gen.w] = gen.floor_id
	new_pos := start_pos
	curr_dir := get_random_direction(false)

	for i in 0 ..< steps {
		tmp_pos := new_pos + curr_dir

		for tmp_pos.x == 0 || tmp_pos.y == 0  \
		|| tmp_pos.x >= gen.w-1 || tmp_pos.y >= gen.h-1 {
			tmp_pos = new_pos + get_random_direction(false)
		}

		gen.cells[tmp_pos.x+tmp_pos.y*gen.w] = gen.floor_id
		new_pos = tmp_pos

		if dir_chance > 0 && rand.float64() <= dir_chance {
			new_dir := get_random_direction(false)
			for (-new_dir) == curr_dir {
				new_dir = get_random_direction(false)
			}
			curr_dir = new_dir
		}
	}
	return new_pos
}


/*******************************************************************************

		Quick Generation Procs

	This is intended for quick use. The results are not ideal for every use case.
	For better results, use the API directly.

*******************************************************************************/
// Creates an empty map, with walls all around.
mapgen_create_empty :: proc(gen: ^MapGen, chance: f64) -> Vec2 {
	mapgen_fill_area(gen, 1, 1, gen.w-2, gen.h-2, chance)
	return mapgen_get_random_position_attempts(gen, 5000)
}

// Creates a very simple dungeon.
mapgen_create_simple_dungeon :: proc(gen: ^MapGen, max_rooms, min_size, max_size: int) -> Vec2 {
	mapgen_make_rooms_random(gen, max_rooms, min_size, max_size)
	mapgen_connect_rooms_naive(gen)
	// connect_rooms_smart()
	pos, _ := mapgen_get_position_in_room(gen)
	return pos
}

// Creates simple caves.
mapgen_create_caves :: proc(gen: ^MapGen, density: f64, birth_rule, death_rule, smooth_steps: int) -> Vec2 {
	mapgen_fill_area(gen, 1, 1, gen.w-2, gen.h-2, density)
	mapgen_create_random_barriers(gen)
	mapgen_smooth_cells(gen, birth_rule, death_rule, smooth_steps)
	mapgen_remove_spikes(gen)
	return mapgen_get_random_position_attempts(gen, 5000)
}

// Creates simple drunk walk caves.
mapgen_create_drunk_caves :: proc(gen: ^MapGen, spawns, steps: int/*, dir_chance*/) -> Vec2 {
	pos := mapgen_get_random_position_in_map(gen)
	for i in 0 ..< spawns {
		pos = mapgen_make_drunk_walk(gen, pos, steps, 0.8)
		pos = mapgen_make_drunk_walk(gen, pos, 30, 0.05)
	}
	// mapgen_make_drunk_walk(gen, pos, steps)
	return mapgen_get_random_position_attempts(gen, 5000)
}


