package ork

import "core:math"


BSP_Config :: struct {
	max_depth     : uint,    // how many levels down the tree can it go and split nodes

	split_chance  : f32,    // percent chance (0..1) to split nodes
	room_chance   : f32,    //  percent chance (0..1) to spawn room in each node

	min_node_size : uint,
	max_node_size : uint,    // Dimension limits of nodes and rooms.
	min_room_size : uint,    // if room limits are 0, the node size will be used
	max_room_size : uint,
}

BSP_Node :: struct {
	x, y, w, h : int,
	is_split   : bool,
	child1     : ^BSP_Node,
	child2     : ^BSP_Node,
	room       : Rect,
	depth      : uint,
}

_bsp_new_node :: proc(x, y, w, h: int, depth: uint) -> ^BSP_Node {
	node := new(BSP_Node)
	node.x = x
	node.y = y
	node.w = w
	node.h = h
	node.depth = depth
	return node
}


// Creates a very simple dungeon.
mapgen_create_bsp_dungeon :: proc(mgen: ^MapGen, cfg: BSP_Config) -> Vec2 {
	root := mapgen_new_bsp(mgen)
	mapgen_bsp_split_tree(mgen, root, cfg)
	_bsp_create_rooms(mgen, root, cfg)

	mapgen_carve_all_rooms(mgen)
	mapgen_connect_rooms_naive(mgen)
	mapgen_delete_bsp_tree(root)

	pos, _ := mapgen_get_position_in_room(mgen)
	return pos
}


mapgen_new_bsp :: proc(mgen: ^MapGen, depth: uint = 0) -> ^BSP_Node {
	return _bsp_new_node(0, 0, mgen.w, mgen.h, depth)
}


mapgen_delete_bsp_tree :: proc(node: ^BSP_Node) {
	if node.child1 != nil do mapgen_delete_bsp_tree(node.child1)
	if node.child2 != nil do mapgen_delete_bsp_tree(node.child2)
	free(node)
}


mapgen_bsp_split_tree :: proc(mgen: ^MapGen, node: ^BSP_Node, cfg: BSP_Config,
                              _should_validate := true, loc:=#caller_location
                             ) {
	if _should_validate do _bsp_validate_config(cfg, loc)

	if node.w > int(cfg.max_node_size) \
	|| node.h > int(cfg.max_node_size) \
	|| f32(randf()) < cfg.split_chance
	{
		mapgen_bsp_split_node(node, cfg, false)
		if node.is_split {
			if node.child1 != nil do mapgen_bsp_split_tree(mgen, node.child1, cfg, false)
			if node.child2 != nil do mapgen_bsp_split_tree(mgen, node.child2, cfg, false)
		}
	}
}


mapgen_bsp_split_node :: proc(node: ^BSP_Node, cfg: BSP_Config,
                              _should_validate:=true, loc:=#caller_location
                             ) {
	if _should_validate do _bsp_validate_config(cfg, loc)
	if node.depth >= cfg.max_depth do return
	horizontal := _mapgen_bsp_should_split_horizontally(node)
	pos, ok := _mapgen_bsp_get_split_position(node, horizontal, cfg.min_node_size, cfg.max_node_size)
	if !ok do return
	_bsp_split(node, horizontal, pos)
}

@private
_bsp_validate_config :: #force_inline proc(cfg: BSP_Config, loc:=#caller_location) {
	assert(cfg.max_depth > 0, loc=loc)
	assert(cfg.max_node_size >= cfg.min_node_size, loc=loc)
	assert(cfg.max_room_size >= cfg.min_room_size, loc=loc)

	assert(cfg.max_room_size <= cfg.max_node_size, loc=loc)
	assert(cfg.min_room_size <= cfg.min_node_size, loc=loc)

}



_mapgen_bsp_should_split_horizontally :: proc(node: ^BSP_Node) -> bool {
	if node.w > node.h do return true
	if node.h > node.w do return false
	return randf() < 0.5
}


_mapgen_bsp_get_split_position :: proc(node: ^BSP_Node, horizontal: bool, min_size, max_size: uint) -> (int, bool) {
	min_size:= int(min_size)
	max_size:= int(max_size)
	if horizontal do max_size = node.w - min_size
	else          do max_size = node.h - min_size

	if max_size <= min_size do return 0, false
	return rand(min_size, max_size), true
}


@private
_bsp_split :: proc(node: ^BSP_Node, horizontal: bool, position: int) -> bool {
	if node.is_split do return false

	p := position
	if horizontal {
		node.child1 = _bsp_new_node( node.x,   node.y, p,        node.h, node.depth+1)
		node.child2 = _bsp_new_node( node.x+p, node.y, node.w-p, node.h, node.depth+1)
	} else {
		node.child1 = _bsp_new_node( node.x, node.y,   node.w, p       , node.depth+1)
		node.child2 = _bsp_new_node( node.x, node.y+p, node.w, node.h-p, node.depth+1)
	}

	node.is_split = true
	return true
}


_bsp_create_rooms :: proc(mgen: ^MapGen, node: ^BSP_Node,
                          cfg: BSP_Config) {
	if node.is_split {
		_bsp_create_rooms(mgen, node.child1, cfg)
		_bsp_create_rooms(mgen, node.child2, cfg)

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

			w = lo == hi_w ? hi_w : rand(lo, hi_w)
			h = lo == hi_h ? hi_h : rand(lo, hi_h)

			if w == node.w do x = 0
			else           do x = rand( 0, node.w-w )

			if h == node.h do y = 0
			else           do y = rand( 0, node.h-h )

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
