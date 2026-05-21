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
	context.random_generator = internal.rng
	mapgen_make_rooms_random(gen, max_rooms, min_size, max_size)
	// mapgen_connect_rooms_sequential(gen)
	mapgen_connect_rooms_directional(gen, randf() > 0.5 )
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



// Creates a dungeon using a binary tree. This results in more adjacent
// and symetrical rooms.
mapgen_create_bsp_dungeon :: proc(mgen: ^MapGen, cfg: BSP_Config) -> Vec2 {
	context.random_generator = internal.rng
	root := mapgen_new_bsp(mgen)

	mapgen_bsp_split_tree(mgen, root, cfg)
	mapgen_bsp_create_rooms(mgen, root, cfg)

	mapgen_carve_all_rooms(mgen)
	mapgen_connect_rooms_sequential(mgen)  // for BSP, I think 'sequential' works better
	// mapgen_connect_rooms_directional(mgen, randf() > 0.5 )

	mapgen_delete_bsp_tree(root)

	pos, _ := mapgen_get_position_in_room(mgen)
	return pos
}



/*******************************************************************************

		General API

*******************************************************************************/
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

		w := rand.int_max(max_size-1)       + min_size
		h := rand.int_max(max_size-1)       + min_size
		x := rand.int_max((mgen.w - w) - 2) + 1
		y := rand.int_max((mgen.h - h) - 2) + 1

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

// Create corridors between rooms using a blind approach of iterating
// through the list of rooms and connecting each room to the next.
mapgen_connect_rooms_sequential :: proc(mgen: ^MapGen) {
	context.random_generator = internal.rng

	for i in 1 ..< len(mgen.rooms) {
		last_idx := i-1 >= 0 ? i-1 : len(mgen.rooms)-1
		room1 := mgen.rooms[last_idx]
		room2 := mgen.rooms[i]

		if rect_touches(room1, room2) do continue

		from := mapgen_get_random_position_in_room(room1)
		to   := mapgen_get_random_position_in_room(room2)
		mid: Vec2

		if randf() > 0.5 do mid = Vec2{to.x, from.y}
		else             do mid = Vec2{from.x, to.y}

		l1 := line_points(from.x, from.y, mid.x, mid.y)
		l2 := line_points(mid.x, mid.y, to.x, to.y)

		mapgen_carve_points(mgen, l1)
		mapgen_carve_points(mgen, l2)
	}
}

// Create corridors between rooms using a guided approach of choosing a
// direction and connecting each room to the closest one in that direction.
mapgen_connect_rooms_directional :: proc(mgen: ^MapGen, horizontal: bool) {
	sort_vert  := proc(a, b: Rect) -> bool { return a.y < b.y }
	sort_horz  := proc(a, b: Rect) -> bool { return a.x < b.x }

	slice.sort_by(mgen.rooms[:], horizontal ? sort_horz : sort_vert)

	mapgen_connect_rooms_sequential(mgen)
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

		BSP Dungeon

*******************************************************************************/
BSP_Config :: struct {
	max_depth     : uint,    // How many levels down the tree can it go and split nodes

	split_chance  : f32,     // Percent chance (0..1) to split nodes
	room_chance   : f32,     // Percent chance (0..1) to spawn room in each node

	min_size      : uint,    // Dimension limits of nodes and rooms.
	max_size      : uint,
	min_room_size : uint,    // if room limits are 0, the node size will be used
	max_room_size : uint,
}

BSP_Node :: struct {
	x, y, w, h : int,
	room       : Rect,
	depth      : uint,

	_is_split   : bool,
	_child1     : ^BSP_Node,
	_child2     : ^BSP_Node,
}

BSP_Room_Callback :: #type proc(^MapGen, ^BSP_Node, BSP_Config) -> Rect


@private _bsp_new_node :: proc(x, y, w, h: int, depth: uint) -> ^BSP_Node {
	node := new(BSP_Node)
	node.x = x
	node.y = y
	node.w = w
	node.h = h
	node.depth = depth
	return node
}

// Returns a new node which is the root of the tree.
mapgen_new_bsp :: proc(mgen: ^MapGen, depth: uint = 0) -> ^BSP_Node {
	return _bsp_new_node(0, 0, mgen.w, mgen.h, depth)
}


// Destroys an entire tree and frees its memory.
mapgen_delete_bsp_tree :: proc(node: ^BSP_Node) {
	if node._child1 != nil do mapgen_delete_bsp_tree(node._child1)
	if node._child2 != nil do mapgen_delete_bsp_tree(node._child2)
	free(node)
}


// Recursively splits the entire tree from the given `node`, creating child
// nodes as needed.
mapgen_bsp_split_tree :: proc(mgen: ^MapGen, node: ^BSP_Node, cfg: BSP_Config,
                              _should_validate := true, loc:=#caller_location
                             ) {
	if _should_validate do _bsp_validate_config(cfg, loc)
	context.random_generator = internal.rng

	if node.w > int(cfg.max_size) \
	|| node.h > int(cfg.max_size) \
	|| f32(randf()) < cfg.split_chance
	{
		mapgen_bsp_split_node(node, cfg, false)
		if node._is_split {
			if node._child1 != nil do mapgen_bsp_split_tree(mgen, node._child1, cfg, false)
			if node._child2 != nil do mapgen_bsp_split_tree(mgen, node._child2, cfg, false)
		}
	}
}


// Splits a single node.
mapgen_bsp_split_node :: proc(node: ^BSP_Node, cfg: BSP_Config,
                              _should_validate:=true, loc:=#caller_location
                             ) {
	if _should_validate do _bsp_validate_config(cfg, loc)
	if node.depth >= cfg.max_depth do return
	horizontal := _mapgen_bsp_should_split_horizontally(node)
	pos, ok := _mapgen_bsp_get_split_position(node, horizontal, cfg.min_size, cfg.max_size)
	if !ok do return
	_bsp_split(node, horizontal, pos)
}


@private _bsp_validate_config :: #force_inline proc(cfg: BSP_Config, loc:=#caller_location) {
	assert(cfg.max_depth > 0, loc=loc)
	assert(cfg.max_size >= cfg.min_size, loc=loc)
	assert(cfg.max_room_size >= cfg.min_room_size, loc=loc)

	assert(cfg.max_room_size <= cfg.max_size, loc=loc)
	assert(cfg.min_room_size <= cfg.min_size, loc=loc)

}


@private _mapgen_bsp_should_split_horizontally :: proc(node: ^BSP_Node) -> bool {
	context.random_generator = internal.rng
	if node.w > node.h do return true
	if node.h > node.w do return false
	return randf() < 0.5
}


@private _mapgen_bsp_get_split_position :: proc(node: ^BSP_Node, horizontal: bool,
                                       min_size, max_size: uint
                                      ) -> (int, bool) {
	context.random_generator = internal.rng

	min_size:= int(min_size)
	max_size:= int(max_size)
	if horizontal do max_size = node.w - min_size
	else          do max_size = node.h - min_size

	if max_size <= min_size do return 0, false
	return randi(min_size, max_size), true
}


@private _bsp_split :: proc(node: ^BSP_Node, horizontal: bool, position: int) -> bool {
	if node._is_split do return false

	p := position
	if horizontal {
		node._child1 = _bsp_new_node( node.x,   node.y, p,        node.h, node.depth+1)
		node._child2 = _bsp_new_node( node.x+p, node.y, node.w-p, node.h, node.depth+1)
	} else {
		node._child1 = _bsp_new_node( node.x, node.y,   node.w, p       , node.depth+1)
		node._child2 = _bsp_new_node( node.x, node.y+p, node.w, node.h-p, node.depth+1)
	}

	node._is_split = true
	return true
}


// Traverses the tree and calls a user callback for each node that can have
// a room, allowing the user to entirely decide how the rooms are built.
mapgen_bsp_create_rooms_callback :: proc(mgen: ^MapGen, node: ^BSP_Node,
                                         cfg: BSP_Config,
                                         callback: BSP_Room_Callback,
                                         loc := #caller_location) {
	// TODO: I'm not too sure about this

	if node._is_split {
		mapgen_bsp_create_rooms(mgen, node._child1, cfg)
		mapgen_bsp_create_rooms(mgen, node._child2, cfg)
	} else {
		room := callback(mgen, node, cfg)
		assert(room.x < mgen.w && room.y < mgen.h, loc=loc)
		assert(room.w > 0 && room.h > 0, loc=loc)

		node.room = room
		append(&mgen.rooms, node.room)
	}
}


// Traverses the tree and creates rooms based on the configuration settings.
mapgen_bsp_create_rooms :: proc(mgen: ^MapGen, node: ^BSP_Node,
                                cfg: BSP_Config) {
	context.random_generator = internal.rng

	if node._is_split {
		mapgen_bsp_create_rooms(mgen, node._child1, cfg)
		mapgen_bsp_create_rooms(mgen, node._child2, cfg)

	} else if randf() < f64(cfg.room_chance) {
		min_size := int(cfg.min_room_size)
		max_size := int(cfg.max_room_size)

		x, y, w, h:int

		if max_size == 0 || min_size == 0 {
			w = node.w-1
			h = node.h-1
		} else {
			lo := min_size
			hi_w := max_size == node.w ? node.w-1 : min(node.w, max_size)
			hi_h := max_size == node.h ? node.h-1 : min(node.h, max_size)

			w = lo == hi_w ? hi_w : randi(lo, hi_w)
			h = lo == hi_h ? hi_h : randi(lo, hi_h)

			if w == node.w do x = 0
			else           do x = randi( 0, node.w-w )

			if h == node.h do y = 0
			else           do y = randi( 0, node.h-h )

		}

		room := Rect{node.x+x, node.y+y, w, h}

		if room.x == 0 do room.x +=1
		if room.y == 0 do room.y +=1

		x2 := room.x + room.w
		y2 := room.y + room.h

		if x2 >= mgen.w {
			diff := (x2-mgen.w)
			room.w -= diff+1
		}

		if y2 >= mgen.h {
			diff := (y2-mgen.h)
			room.h -= diff+1
		}

		if room.w >= min_size && room.h >= min_size {
			node.room = room
			append(&mgen.rooms, node.room)
		}
	}
}



