#+feature dynamic-literals
package examples

import "core:math"

import ork "../"  // Ork itself


@(private="file") gmap     : GameMap
@(private="file") astar    : ^ork.AStar

@(private="file") title := "A* Pathfinding Test (Ork)"
@(private="file") player := Entity { {}, '@', ork.AMBER7, ork.BLACK }
@(private="file") enemy  := Entity { {}, 'E', ork.BLUE7,  ork.BLACK }

debug_draw_search_sets := false


draw_astar_path :: proc() {
	path := ork.astar_compute_path(astar, player.pos, enemy.pos)

	if len(path) == 0 do return
	if debug_draw_search_sets {
		for node, _ in astar._closed_table {
			ork.draw_bg(ex_console, node.x, node.y, ork.BLUE1)
		}

		for node in astar._open_queue.queue {
			ork.draw_bg(ex_console, node.x, node.y, ork.DPINK1)
		}
	}

	for p in path {
		ork.draw_cell(ex_console, p.x, p.y, '.', ork.RED4, ork.BLACK)
	}
}



astar_example_init :: proc() {
	gmap.map_type = MapType.Dungeon

	init_map(GW, GH, &gmap, &player)
	init_enemy(&enemy, &gmap)

	check_cell :: proc(astar: ^ork.AStar, x, y: int) -> bool {
		return gmap.tiles[x+y*astar.w].walkable
	}
	set_costs :: proc(astar: ^ork.AStar, x, y: int) -> f32 {
		return gmap.tiles[x+y*astar.w].type == .Water ? 20 : 1
	}

	// This example isn't using an FOV, but we still need a fovmap so the
	// pathfinding knows the layout of the map, unless we use the 'check_cell'
	// override, where we can check our tiles directly.
	// IMPORTANT: for convenience, 'astar' keeps a pointer to our fovmap, so
	// if we destroy the fovmap then 'astar' can't compute the path anymore.
	// If we create a new fovmap, we need to update 'astar.fovmap' to point to it.
	astar = ork.new_astar(gmap.fovmap)
	// astar = ork.create_astar(gmap.w, gmap.h, check_cell)

	ork.astar_set_costs(astar, set_costs)
}


astar_example_update :: proc() {
	if !in_menu {
		if      ork.mouse_down({.MouseLeft})  do paint_tile(&gmap, .Wall)
		else if ork.mouse_down({.MouseRight}) do paint_tile(&gmap, .Floor)

		dir := ork.VEC2_ZERO
		if ork.action_repeat("move_left")  do dir.x -= 1
		if ork.action_repeat("move_right") do dir.x += 1
		if ork.action_repeat("move_up")    do dir.y -= 1
		if ork.action_repeat("move_down")  do dir.y += 1

		if dir != ork.VEC2_ZERO {
		 	player_moved = try_move(gmap, &player, dir.x, dir.y)
		}
	}

	if ork.key_pressed({.Space}) {
		gmap.map_type = MapType(math.wrap(f32(gmap.map_type)+1, len(MapType)))
		init_map(GW, GH, &gmap, &player)
		init_enemy(&enemy, &gmap)
		should_redraw = true
	}

	if ork.key_pressed({.N1}) {
		debug_draw_search_sets = !debug_draw_search_sets
	}

	if !player_moved && !should_redraw do return

	ork.clear_cells(ex_console)

	draw_tiles(&gmap)
	draw_astar_path()
	ork.draw_cell(ex_console, player.x, player.y, player.glyph, player.fg, player.bg)
	ork.draw_cell(ex_console, enemy.x, enemy.y, enemy.glyph, enemy.fg, enemy.bg)

	player_moved = false
	should_redraw = false
}


astar_example_render :: proc() {
	ork.render(ex_console)
	// ork.set_window_title(fmt.tprintf("%s - %d fps", title, ork.get_fps_smoothed()))
}

astar_example_quit :: proc() {
	delete(gmap.tiles)
	ork.delete_mapgen(gmap.mapgen)
}
