package ork

import "core:slice"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:mem/virtual"
import pq "core:container/priority_queue"





DIAGONAL_DISTANCE :: 1.4142135623730951

Path_Node :: struct {
	x, y     : int,
	// walkable : bool,
	cost     : f32,
	distance : f32,  // gcost in A*
	inv_dist : f32,  // hcost in A*
	parent   : ^Path_Node,
}

Path_Callback      :: proc(data: ^Path_Data, #any_int x, y: int) -> bool
Path_Cost_Callback :: proc(data: ^Path_Data, #any_int x, y: int) -> f32

Path_Data :: struct {
	w, h        : int,
	arena       : virtual.Arena,
	allocator   : mem.Allocator,
	fovmap      : ^Fovmap,
	nodes       : []Path_Node,
	path        : [dynamic]Vec2,
	_check_cell  : Path_Callback,
	diag_cost   : f32,
}

Dijkstra_Map :: struct {
	using data : Path_Data,
	_root      : ^Path_Node,
}


AStar :: struct {
	using data    : Path_Data,
	allow_corners : bool,
	success       : bool,
	_closed_table : map[^Path_Node]bool,  // temp for debugging
	_open_queue   : pq.Priority_Queue(^Path_Node),
}

Path :: union {
	^Dijkstra_Map,
	^AStar,
}

@private _create_node :: proc(#any_int x, y: int, distance: f32/*, walkable: bool, */) -> Path_Node {
	return {
		x        = x,
		y        = y,
		// walkable = walkable,
		cost     = 1,
		distance = distance, //math.INF_F32,
	}
}


@private _new_field :: proc(data: ^Path_Data, initial_distance: f32) -> []Path_Node {
	nodes := make([]Path_Node, data.w*data.h, data.allocator)
	for j in 0 ..< data.h {
		for i in 0 ..< data.w {
			nodes[i+j*data.w] = _create_node(i, j, initial_distance)
		}
	}
	return nodes
}


@private _destroy_data :: proc(data: ^Path_Data) {
	delete(data.path)
	free_all(data.allocator)
	virtual.arena_destroy(&data.arena)
}


@private _init_path_data :: proc(data: ^Path_Data, #any_int w, h: int,
                         diag_cost: f32, fm: Maybe(^Fovmap) = nil,
                         callback: Maybe(Path_Callback) = nil
                         ) {
	data.allocator = virtual.arena_allocator(&data.arena)
	data.w = w
	data.h = h
	data.diag_cost = diag_cost

	if fmp, ok := fm.?; ok {
		data.fovmap = fmp
	}

	if cb, ok := callback.?; ok {
		data._check_cell = cb
	} else {
		data._check_cell = proc(data: ^Path_Data, #any_int x, y: int) -> bool {
			return data.fovmap.cells[x+y*data.w].walkable
		}
	}
}


/*******************************************************************************

		Dijstra Map

*******************************************************************************/
delete_dijkstra :: proc(dij: ^Dijkstra_Map, loc := #caller_location) {
	if dij == nil do return
	idx, ok := _get_item_index(internal.paths[:], (Path)(dij))
	if ok do unordered_remove(&internal.paths, idx)
	_destroy_data(&dij.data)
	free(dij)
}


new_dijkstra :: proc {
	new_dijkstra_with_map,
	new_dijkstra_with_callback,
}

new_dijkstra_with_map :: proc(fm: ^Fovmap,
                                diag_cost: f32 = DIAGONAL_DISTANCE
                             ) -> ^Dijkstra_Map {
	path := _create_dijkstra_with_map(fm, diag_cost)
	append(&internal.paths, (Path)(path))
	return path
}

new_dijkstra_with_callback :: proc(#any_int w, h: int,
                                     callback: Maybe(Path_Callback) = nil,
                                     diag_cost: f32 = DIAGONAL_DISTANCE
                                  ) -> ^Dijkstra_Map {
	path := _create_dijkstra_with_callback(w, h, callback, diag_cost)
	append(&internal.paths, (Path)(path))
	return path
}



@private _create_dijkstra_with_map :: proc(fm: ^Fovmap, diag_cost: f32 = DIAGONAL_DISTANCE) -> ^Dijkstra_Map {
	return _create_dijkstra_impl(fm.w, fm.h, fm, nil, diag_cost)
}

@private _create_dijkstra_with_callback :: proc(#any_int w, h: int, callback: Maybe(Path_Callback) = nil, diag_cost: f32 = DIAGONAL_DISTANCE) -> ^Dijkstra_Map {
	return _create_dijkstra_impl(w, h, nil, callback, diag_cost)
}

@private _create_dijkstra_impl :: proc(w, h: int, fm: Maybe(^Fovmap) = nil,
					callback: Maybe(Path_Callback) = nil,
					diag_cost: f32 = DIAGONAL_DISTANCE) -> ^Dijkstra_Map {
	dij := new(Dijkstra_Map)
	dij.data = Path_Data{}
	_init_path_data(&dij.data, w, h, diag_cost, fm, callback)
	dij.nodes = _new_field(&dij.data, math.INF_F32)
	dijkstra_set_diagonal_cost(dij, diag_cost)
	return dij
}


@private reset_dij :: proc(dij: ^Dijkstra_Map) {
	data := &dij.data
	clear(&data.path)

	root_dist := dij._root.distance
	for &n in data.nodes {
		n.distance = math.INF_F32
		n.parent = nil
	}

	dij._root.distance = root_dist
}


dijkstra_set_root :: proc(dij: ^Dijkstra_Map, x, y: int, distance: f32, cost: f32 = 1) {
	dij._root = &dij.nodes[x+y*dij.w]
	dij._root.distance = distance
	dij._root.cost = cost
	clear(&dij.path)
}


dijkstra_set_diagonal_cost :: proc(dij: ^Dijkstra_Map, new_cost: f32) {
	new_cost := max(0, new_cost)
	dij.diag_cost = new_cost
}


dijkstra_set_costs :: proc(dij: ^Dijkstra_Map, callback: Path_Cost_Callback) {
	for j in 0 ..< dij.h {
		for i in 0 ..< dij.w {
			dij.nodes[i].cost = callback(dij, i, j)
		}
	}
}


dijkstra_set_cost :: proc(dij: ^Dijkstra_Map, x, y: int, cost: f32) {
	dij.nodes[x+y*dij.w].cost = cost
}


dijkstra_compute_path :: proc(dij: ^Dijkstra_Map, sx, sy: int, reversed := true, loc := #caller_location) -> [dynamic]Vec2 {
	if dij._root == nil do fmt.panicf("dijkstra map has no root set", loc=loc)

	clear(&dij.path)

	curr_node := &dij.nodes[sx+sy*dij.w]
	end_node  := dij._root

	for curr_node != nil && curr_node != end_node {
		append(&dij.path, Vec2{curr_node.x, curr_node.y})
		curr_node = curr_node.parent
	}

	if reversed do slice.reverse(dij.path[:])
	return dij.path
}


dijkstra_compute_map :: proc(dij: ^Dijkstra_Map) {
	reset_dij(dij)

	candidates: [dynamic]^Path_Node
	new_candidates: [dynamic]^Path_Node
	defer delete(new_candidates)
	defer delete(candidates)

	append(&candidates, dij._root)

	for len(candidates) > 0 {
		clear(&new_candidates)

		for idx in 0 ..< len(candidates) {
			c := candidates[idx]
			curr_dist := c.distance
			curr_cost_diag := (curr_dist-1) + dij.diag_cost

			// check the 8 neighbors
			for i in 0 ..< 8 {
				cost := curr_dist
				if i >= 4 do cost = curr_cost_diag
				nx := c.x + DIRECTIONS[Direction(i)].x
				ny := c.y + DIRECTIONS[Direction(i)].y

				if nx >= 0 && ny >= 0 && nx < dij.w && ny < dij.h \
				&& dij._check_cell(dij, nx, ny)
				{
					nb := &dij.nodes[nx+ny*dij.w]
					cost += nb.cost
					if nb.distance > cost {
						nb.distance = cost
						nb.parent = c
						append(&new_candidates, nb)
					}
				}
			}
		}
		clear(&candidates)
		for i in 0 ..< len(new_candidates) {
			append(&candidates, new_candidates[i])
		}
	}
}




/*******************************************************************************

		AStar

*******************************************************************************/
/*

		TODO:
			- add callback to
*/


delete_astar :: proc(astar: ^AStar, loc := #caller_location) {
	if astar == nil do return
	idx, ok := _get_item_index(internal.paths[:], (Path)(astar))
	if ok do unordered_remove(&internal.paths, idx)

	_destroy_data(&astar.data)
	delete(astar._closed_table)
	pq.destroy(&astar._open_queue)
	free(astar)
}

new_astar :: proc {
	new_astar_with_map,
	new_astar_with_callback,
}

new_astar_with_map :: proc(fm: ^Fovmap, diag_cost: f32 = DIAGONAL_DISTANCE
                             ) -> ^AStar {
	path := _create_astar_with_map(fm, diag_cost)
	append(&internal.paths, (Path)(path))
	return path
}

new_astar_with_callback :: proc(#any_int w, h: int,
                                   callback: Maybe(Path_Callback) = nil,
                                   diag_cost: f32 = DIAGONAL_DISTANCE
                              ) -> ^AStar {
	path := _create_astar_with_callback(w, h, callback, diag_cost)
	append(&internal.paths, (Path)(path))
	return path
}



astar_set_costs :: proc(astar: ^AStar, callback: Path_Cost_Callback) {
	for j in 0 ..< astar.h {
		for i in 0 ..< astar.w {
			astar.nodes[i].cost = callback(astar, i, j)
		}
	}
}


astar_compute_path :: proc(astar: ^AStar, from, to: Vec2) -> [dynamic]Vec2 {
	astar.success = false

	pq.clear(&astar._open_queue)
	clear(&astar._closed_table)

	start_node := &astar.nodes[from.x+from.y*astar.w]
	target_node := &astar.nodes[to.x+to.y*astar.w]

	pq.push(&astar._open_queue, start_node)

	for pq.len(astar._open_queue) > 0 {
		// make current node the node in 'astar._open_queue' with lowest 'fcost'

		currn := pq.pop(&astar._open_queue)
		astar._closed_table[currn] = true

		// if currn == target_node, then we found the path
		if currn == target_node {
			_retrace_path(astar, start_node, target_node)
			astar.success = true
			return astar.path
		}

		neighbs := _get_neighbors(astar, currn)

		// for i in 0 ..< len(neighbs) {
			// nb := neighbs[i]
		for &nb in neighbs {
			if nb == nil do continue
			new_cost := currn.distance + _astar_dist(currn^, nb^, astar.diag_cost) + nb.cost
			nb_idx, nb_in_queue := slice.linear_search(astar._open_queue.queue[:], nb)
			if new_cost < nb.distance || !nb_in_queue {
				nb.distance = new_cost
				nb.inv_dist = _astar_dist(nb^, target_node^, astar.diag_cost)
				nb.parent = currn

				if !nb_in_queue {
					pq.push(&astar._open_queue, nb)
				} else {
					pq.fix(&astar._open_queue, nb_idx)
				}
			}
		}
	}

	return {}
}



@private _create_astar_with_map :: proc(fm: ^Fovmap, diag_cost: f32 = DIAGONAL_DISTANCE) -> ^AStar {
	return _create_astar_impl(fm.w, fm.h, fm, nil, diag_cost)

}

@private _create_astar_with_callback :: proc(#any_int w, h: int, callback: Maybe(Path_Callback) = nil, diag_cost: f32 = DIAGONAL_DISTANCE) -> ^AStar {
	return _create_astar_impl(w, h, nil, callback, diag_cost)
}

@private _create_astar_impl :: proc(w, h: int, fm: Maybe(^Fovmap) = nil,
	            callback: Maybe(Path_Callback) = nil,
	            diag_cost: f32 = DIAGONAL_DISTANCE) -> ^AStar {

	astar := new(AStar)
	astar.data = Path_Data{}
	_init_path_data(&astar.data, w, h, diag_cost, fm, callback)
	astar.nodes = _new_field(&astar.data, 0)
	// set_diagonal_cost(astar, diag_cost)
	pq.init(&astar._open_queue, _check_lower_priority, pq.default_swap_proc(^Path_Node))
	return astar
}

@private _fcost :: proc(n: ^Path_Node) -> f32 {
	return n.distance + n.inv_dist
}

@private _check_lower_priority :: proc(a, b: ^Path_Node) -> bool {
	return _fcost(a) < _fcost(b)
}




@private _astar_dist :: proc(a, b: Path_Node, diag_dist: f32) -> f32 {
	distx := f32(abs(a.x - b.x))
	disty := f32(abs(a.y - b.y))
	if distx > disty do return diag_dist*disty + (distx-disty)
	return diag_dist*distx + (disty-distx)
}

@private _retrace_path :: proc(astar: ^AStar, start_node, end_node: ^Path_Node, reversed := false) -> [dynamic]Vec2 {
	clear(&astar.path)

	curr_node := end_node

	for curr_node != nil && curr_node != start_node {
		append(&astar.path, Vec2{curr_node.x, curr_node.y})
		curr_node = curr_node.parent
	}

	if reversed do slice.reverse(astar.path[:])
	return astar.path
}


@private _get_node_ptr :: proc(astar: ^AStar, x, y: int) -> ^Path_Node {
	return &astar.nodes[x+y*astar.w]
}


@private _get_neighbors :: proc(astar: ^AStar, curr_node: ^Path_Node) -> [8]^Path_Node {
	x, y := curr_node.x, curr_node.y
	l, r, u, d := curr_node.x-1, curr_node.x+1, curr_node.y-1, curr_node.y+1

	nb_l, nb_ul, nb_dl, nb_u, nb_d, nb_r, nb_ur, nb_dr: ^Path_Node

	if l >= 0 {
		nb_l  = _get_node_ptr(astar, l, y)
		if u >= 0      do nb_ul = _get_node_ptr(astar, l, u)
		if d < astar.h do nb_dl = _get_node_ptr(astar, l, d)
	}

	if u >= 0      do nb_u = _get_node_ptr(astar, x, u)
	if d < astar.h do nb_d = _get_node_ptr(astar, x, d)

	if r < astar.w {
		nb_r  = _get_node_ptr(astar, r, y)
		if u >= 0      do nb_ur = _get_node_ptr(astar, r, u)
		if d < astar.h do nb_dr = _get_node_ptr(astar, r, d)
	}

	// NOTE: the order matters: orthogonals first, diagonals last
	neighbs: [8]^Path_Node

	if nb_l  != nil && !astar._closed_table[nb_l]  && astar._check_cell(astar, l, y) do neighbs[0] = nb_l
	if nb_r  != nil && !astar._closed_table[nb_r]  && astar._check_cell(astar, r, y) do neighbs[1] = nb_r
	if nb_u  != nil && !astar._closed_table[nb_u]  && astar._check_cell(astar, x, u) do neighbs[2] = nb_u
	if nb_d  != nil && !astar._closed_table[nb_d]  && astar._check_cell(astar, x, d) do neighbs[3] = nb_d

	if nb_ul != nil && !astar._closed_table[nb_ul] && astar._check_cell(astar, l, u) do neighbs[4] = nb_ul
	if nb_ur != nil && !astar._closed_table[nb_ur] && astar._check_cell(astar, r, u) do neighbs[5] = nb_ur
	if nb_dl != nil && !astar._closed_table[nb_dl] && astar._check_cell(astar, l, d) do neighbs[6] = nb_dl
	if nb_dr != nil && !astar._closed_table[nb_dr] && astar._check_cell(astar, r, d) do neighbs[7] = nb_dr

	return neighbs
}






