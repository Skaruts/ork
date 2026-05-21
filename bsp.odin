package ork

import "core:math"

BSP_Gen_Config :: struct {
	split_chance  : f32,
	room_chance   : f32,
	min_leaf_size : int,
	max_leaf_size : int,
	min_room_size : int,
	max_room_size : int,
}

BSP_Leaf :: struct {
	x, y, w, h : int,
	is_split   : bool,
	child1     : ^BSP_Leaf,
	child2     : ^BSP_Leaf,
	room       : Rect,
	// tunnel   = nil,
}


// Creates a very simple dungeon.
mapgen_create_bsp_dungeon :: proc(gen: ^MapGen, config: BSP_Gen_Config) -> Vec2 {
	leaves, root := mapgen_make_rooms_bsp(gen, config)
	mapgen_carve_all_rooms(gen)
	mapgen_connect_rooms_naive(gen)
	// connect_rooms_smart()
	_bsp_free_node(root)
	delete(leaves)
	pos, _ := mapgen_get_position_in_room(gen)
	return pos
}


_bsp_free_node :: proc(node: ^BSP_Leaf) {
	if node.child1 != nil do _bsp_free_node(node.child1)
	if node.child2 != nil do _bsp_free_node(node.child2)
	free(node)
}


mapgen_make_rooms_bsp :: proc(mgen: ^MapGen, config: BSP_Gen_Config) -> ([dynamic]^BSP_Leaf, ^BSP_Leaf) {
	context.random_generator = internal.rng
	clear(&mgen.rooms)

	leaves : [dynamic]^BSP_Leaf
	root_leaf := _bsp_new_leaf(0, 0, mgen.w, mgen.h)

	append(&leaves, root_leaf)

	can_split := true

	for can_split {
		can_split = false
		for leaf, i in leaves {
			if leaf.w > config.max_leaf_size \
			|| leaf.h > config.max_leaf_size \
			|| f32(randf()) < config.split_chance
			{
				if _bsp_split(mgen, leaf, config.min_leaf_size, config.max_leaf_size) {
					append(&leaves, leaf.child1)
					append(&leaves, leaf.child2)
					can_split = true
				}
			}
		}
	}

	_bsp_create_room(root_leaf, &mgen.rooms, config.room_chance, config.min_room_size, config.max_room_size)
	return leaves, root_leaf
}


_bsp_new_leaf :: proc(x, y, w, h: int) -> ^BSP_Leaf {
	leaf := new(BSP_Leaf)
	leaf.x = x
	leaf.y = y
	leaf.w = w
	leaf.h = h
	return leaf
}


_bsp_split :: proc(mgen: ^MapGen, leaf: ^BSP_Leaf, min_size, max_size: int) -> bool {
	if leaf.is_split do return false

	direction : rune
	max_size  : int

	if      leaf.w > leaf.h do direction = 'H'
	else if leaf.h > leaf.w do direction = 'V'
	else {
		direction = randf() > 0.5 ? 'V' : 'H'
	}
	if direction == 'V' do max_size = leaf.h - min_size
	else                do max_size = leaf.w - min_size

	if max_size <= min_size do return false

	split_pos := rand(min_size, max_size)

	if direction == 'V' {
		leaf.child1 = _bsp_new_leaf( leaf.x, leaf.y, leaf.w, split_pos )
		leaf.child2 = _bsp_new_leaf( leaf.x, leaf.y+split_pos, leaf.w, leaf.h-split_pos )
	} else {
		leaf.child1 = _bsp_new_leaf( leaf.x, leaf.y, split_pos, leaf.h )
		leaf.child2 = _bsp_new_leaf( leaf.x+split_pos, leaf.y, leaf.w-split_pos, leaf.h )
	}

	leaf.is_split = true
	return true
}


_bsp_create_room :: proc(leaf: ^BSP_Leaf, rooms: ^[dynamic]Rect,
	                     room_chance: f32,
	                     min_room_size, max_room_size: int
	                    ) {
	if leaf.is_split {
		// _log:print("creating room in children", leaf, leaf.room)
		_bsp_create_room(leaf.child1, rooms, room_chance, min_room_size, max_room_size)
		_bsp_create_room(leaf.child2, rooms, room_chance, min_room_size, max_room_size)
	// 75% chance of creating a room, so not all leaves will have one
	} else if randf() < f64(room_chance) {
		rw := rand( min_room_size, min(leaf.w-2, max_room_size) )
		rh := rand( min_room_size, min(leaf.h-2, max_room_size) )
		rx := rand( 1, leaf.w-1-rw )
		ry := rand( 1, leaf.h-1-rh )

		leaf.room = Rect{leaf.x+rx, leaf.y+ry, rw, rh}
		append(rooms, leaf.room)
	}
}
