#+feature dynamic-literals
package examples


import "core:math"

import ork "../"  // Ork itself
import "../libs/ui"


@(private="file") gmap   : GameMap
@(private="file") dij    : ^ork.Dijkstra_Map

@(private="file") title  := "Dijkstra Pathfinding Test (Ork)"
@(private="file") player := Entity { {}, '@', ork.AMBER7, ork.BLACK }
@(private="file") enemy  := Entity { {}, 'E', ork.BLUE7,  ork.BLACK }

@(private="file") debug_draw_heat_map  := false
@(private="file") debug_draw_distances := false
@(private="file") debug_draw_path      := true

@(private="file")
_LETTERS := [?]ork.Rune {
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
	'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
	'U', 'V', 'W', 'X', 'Y', 'Z',
}

@(private="file")
gradient := [?]ork.Color {
	{255, 255,   0, 255}, // 0
	{255, 128,   0, 255}, // 4
	{255,   0,   0, 255}, // 8

	{255,   0, 128, 255}, // 12
	{128,   0, 255, 255}, // 16
	{  0,   0, 255, 255}, // 20
	{  0,   0, 128, 255}, // 24
	{  0,   0,  32, 255}, // 28
	{  0,   0,  32, 255}, // 32

	{ 32,   0,  32, 255}, // 36
}

@(private="file") heatmap_steps := 4



_draw_heatmap :: proc() {
	for j in 0 ..< gmap.h {
		for i in 0 ..< gmap.w {
			if !gmap.tiles[i+j*gmap.w].walkable {
				ork.draw_cell(ex_console, i, j, '#', ork.GREY3)
				// ork.draw_cell(ex_console, i, j, ' ', nil, ork.GREY3)
			} else {
				val := clamp( int( dij.nodes[i+j*gmap.w].distance ), -35, 35)
				gradt_pos := max(0, int( min(val, 35) / heatmap_steps))

				c1 := gradient[gradt_pos]
				c2 := val < 0 ? gradient[max(0, gradt_pos-1)] : gradient[min(len(gradient)-1, gradt_pos+1)]
				percent := (abs(f32(val % heatmap_steps)*100) / f32(heatmap_steps) / 100)

				c3 := ork.color_lerped(c1, c2, percent)
				if val == -35 do c3 = gradient[len(gradient)-1]
				// ork.draw_bg(ex_console, i, j, val < 0 ? ork.color_darkened(c3, 1.5) : c3)
				ork.draw_bg(ex_console, i, j, val < 0 ? c3 : c3)
			}
		}
	}
}

_draw_dists :: proc() {
	for j in 0 ..< gmap.h {
		for i in 0 ..< gmap.w {
			if gmap.tiles[i+j*gmap.w].walkable {
				val := clamp( int(dij.nodes[i+j*gmap.w].distance), -35, 35)
				glyph := _LETTERS[ abs(val) ]

				ork.draw_cell(ex_console, i, j, glyph, ork.DGRAY1)
			}
		}
	}
}

_recompute_dijkstra :: proc() {
	ork.dijkstra_set_root(dij, player.x, player.y, 0) // distance value can be negative
	ork.dijkstra_compute_map(dij)
}


@(private="file") _draw_ui :: proc() {
	y := ui.next_y()
	ui.container("Dijkstra", {0, y, UI_WIDTH+1, MAIN_GH-y}); {
		y = 2
		if ui.checkbox({1, y}, "Heat Map", &debug_draw_heat_map).value_changed {
			should_redraw = true
		}
		ui.text({ui.next_x()+1, y}, "(N1)", UI_TEXT_HOTKEYS)

		y = ui.next_y()
		if ui.checkbox({1, y}, "Dists", &debug_draw_distances).value_changed {
			should_redraw = true
		}
		ui.text({ui.next_x()+1, y}, "(N2)", UI_TEXT_HOTKEYS)

		y = ui.next_y()
		if ui.checkbox({1, y}, "Path", &debug_draw_path).value_changed {
			should_redraw = true
		}
		ui.text({ui.next_x()+1, y}, "(N3)", UI_TEXT_HOTKEYS)
	}
	ui.end_container()
}


dij_example_init :: proc() {
	gmap.map_type = MapType.Caves

	init_map(GW, GH, &gmap, &player)
	init_enemy(&enemy, &gmap)

	check_cell :: proc(dij: ^ork.Dijkstra_Map, x, y: int) -> bool {
		return gmap.tiles[x+y*dij.w].walkable
	}

	set_costs :: proc(dij: ^ork.Dijkstra_Map, x, y: int) -> f32 {
		return gmap.tiles[x+y*dij.w].type == .Water ? 20 : 1
	}

	// This example isn't using an FOV, but we still need a fovmap so the
	// pathfinding knows the layout of the map, unless we use the 'check_cell'
	// override, where we can check our tiles directly.
	// IMPORTANT: for convenience, 'dij' keeps a pointer to our fovmap, so
	// if we destroy the fovmap then 'dij' can't compute the path anymore.
	// If we create a new fovmap, we need to update 'dij.fovmap' to point to it.
	dij = ork.new_dijkstra(gmap.fovmap)
	// dij = ork.create_dijkstra(gmap.w, gmap.h, check_cell)

	ork.dijkstra_set_costs(dij, set_costs)

	// do the initial computation.
	// _recompute_dijkstra()
}


dij_example_update :: proc() {
	_draw_ui()

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

	if ork.key_pressed({.N1}) {
		debug_draw_heat_map = !debug_draw_heat_map
		should_redraw = true
	}

	if ork.key_pressed({.N2}) {
		debug_draw_distances = !debug_draw_distances
		should_redraw = true
	}

	if ork.key_pressed({.N3}) {
		debug_draw_path = !debug_draw_path
		should_redraw = true
	}

	if ork.key_pressed({.Space}) {
		gmap.map_type = MapType(math.wrap(f32(gmap.map_type)+1, len(MapType)))
		init_map(GW, GH, &gmap, &player)
		init_enemy(&enemy, &gmap)
		should_redraw = true
	}

	if !player_moved && !should_redraw do return

	ork.clear_cells(ex_console)

	_recompute_dijkstra()
	draw_tiles(&gmap)

	ork.draw_cell(ex_console, player.x, player.y, player.glyph, player.fg, player.bg)
	ork.draw_cell(ex_console, enemy.x, enemy.y, enemy.glyph, enemy.fg, enemy.bg)

	if debug_draw_heat_map  do _draw_heatmap()
	if debug_draw_distances do _draw_dists()

	if debug_draw_path {
		path := ork.dijkstra_compute_path(dij, enemy.x, enemy.y)
		for p in path {
			if p != enemy.pos {
				if debug_draw_distances && debug_draw_heat_map {
					ork.draw_fg(ex_console, p.x, p.y, ork.GREEN5)
				} else {
					ork.draw_bg(ex_console, p.x, p.y, ork.GREEN5)
				}
			} else if debug_draw_heat_map {
				ork.draw_bg(ex_console, p.x, p.y, ork.GREEN5)
			}
		}
	}

	player_moved = false
	should_redraw = false
}


dij_example_render :: proc() {

	ork.render(ex_console)
}



dij_example_quit :: proc() {
	delete(gmap.tiles)
}
