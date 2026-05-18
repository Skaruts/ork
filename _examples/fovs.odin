package examples

import "core:math"
import "core:fmt"

import ork "../"  // Ork itself


@(private="file") title := "FOV Example (Ork)"
@(private="file") gmap  : GameMap

@(private="file") player := Entity { {}, '@', ork.AMBER7, ork.BLACK }

@(private="file") fov_names : [len(ork.FovType)]string
@(private="file") curr_fov  := ork.FovType.Restrictive

@(private="file") fov_light_walls := true

@(private="file") theme := 0
@(private="file") ground_tile, wall_tile: Tile




UI_TEXT_SELECTED_COL :: ork.AMBER5


_draw_option_group :: proc(x, y: int, name: string, options: []string, selected_idx: int) -> int {
	y := y

	if name != "" {
		ork.draw_text(ui_console, x+1, y, name, UI_HEADER_COL, ork.BLACK)
		y += 2
	}

	for opt_name, i in options {
		if i != selected_idx {
			ork.draw_text(ui_console, x+3, y+i, opt_name, UI_TEXT_FADED_COL, ork.BLACK)
		} else {
			ork.draw_cell(ui_console, x+1, y+i, ork.Index(16), UI_TEXT_SELECTED_COL, ork.BLACK)
			ork.draw_text(ui_console, x+3, y+i, opt_name, UI_TEXT_SELECTED_COL, ork.BLACK)
		}
	}

	y += 2 + len(options)

	return y+2
}


_draw_ui :: proc() {
	x, y := 0, 25
	ork.draw_line(ui_console, x, y, UI_WIDTH-1, y, LINE_H, ork.GRAY1)

	y += 2
	y = _draw_option_group(x, y, "FOV (home/end)", fov_names[:], int(curr_fov))
	y = _draw_option_group(x, y, "Vis (ins/del)", {fmt.tprintf("radius: %d", fov_radius)}, 0)
}


switch_fov :: proc(dir: int) {
	if dir == 0 do return
	curr_fov = ork.FovType( math.wrap(f32(int(curr_fov) + dir), f32(len(ork.FovType))) )
	should_redraw = true
}


set_fov_range :: proc(dir: int) {
	if dir == 0 do return
	fov_radius = math.clamp(fov_radius+dir, 1, 80)
	should_redraw = true
}

paint_cell :: proc(tile_type: TileType) {
	mouse := ork.get_mouse_position(ex_console)
	mx, my := mouse.x, mouse.y

	// don't allow removing the edges, to prevent crashes
	if mx < 1 || mx >= gmap.w-1 || my < 1 || my >= gmap.h-1 do return

	idx := mx+my*gmap.w
	if tile_type == gmap.tiles[idx].type do return
	gmap.tiles[idx] = tile_type == .Wall ? new_tile(wall_tile) : new_tile(ground_tile)

	tile := gmap.tiles[idx]
	ork.fov_set_cell(gmap.fovmap, mx, my, tile.transparent, tile.walkable)
	should_redraw = true
}


// _switch_gen :: proc() {
// 	curr_gen = (curr_gen+1) % 4
// 	init_map()
// 	init_fov()
// 	should_redraw = true
// }

_restart_map :: proc() {
	for j in 0 ..< gmap.h {
		for i in 0 ..< gmap.w {
			gmap.tiles[i+j*gmap.w].explored = false
		}
	}
	ork.fov_clear(gmap.fovmap)
	should_redraw = true
}


fovs_example_init :: proc() {
	for type, i in ork.FovType {
		fov_names[i] = fmt.aprintf("%s", type)
	}

	init_map(GW, GH, &gmap, &player)  // the fov is initialized in 'init_map'
}



fovs_example_quit :: proc() {
	delete(gmap.tiles)
	for name in fov_names {
		delete(name)
	}
}


_handle_input :: proc() {
	if      ork.mouse_down({.MouseLeft})  do paint_cell(.Wall)
	else if ork.mouse_down({.MouseRight}) do paint_cell(.Floor)

	else if ork.key_pressed({.Space}) {
		gmap.map_type = MapType(math.wrap(f32(gmap.map_type)+1, len(MapType)))
		init_map(GW, GH, &gmap, &player)
		should_redraw = true
	}
	else if ork.key_pressed({.R}) {
		fov_light_walls = !fov_light_walls
		_restart_map()
		ork.print("light walls: ", fov_light_walls)
	}
	else if ork.key_pressed({.F}) {
		show_fog_of_war = !show_fog_of_war
		should_redraw = true
	}
	else if ork.key_pressed({.N1, .Home})  do switch_fov(-1)
	else if ork.key_pressed({.N2, .End})   do switch_fov( 1)
	else if ork.key_repeat({.N3, .Insert}) do set_fov_range( 1)
	else if ork.key_repeat({.N4, .Delete}) do set_fov_range(-1)
}


fovs_example_update :: proc() {
	_handle_input()

	dir := ork.Vec2{}
	if ork.action_repeat("move_left")  do dir.x -= 1
	if ork.action_repeat("move_right") do dir.x += 1
	if ork.action_repeat("move_up")    do dir.y -= 1
	if ork.action_repeat("move_down")  do dir.y += 1

	if dir != ork.VEC2_ZERO {
		player_moved = try_move(gmap, &player, dir.x, dir.y)
	}

	if !player_moved && !should_redraw do return

	ork.clear_cells(ex_console)
	ork.fov_compute(gmap.fovmap, player.pos, fov_radius, curr_fov, fov_light_walls)
	draw_tiles_fov(ex_console, &gmap)
	ork.draw_cell(ex_console, player.pos.x, player.pos.y, player.glyph, player.fg, player.bg)

	player_moved = false
	should_redraw = false
}


fovs_example_render :: proc() {
	_draw_ui()

	ork.render(ex_console)

	// ork.set_window_title(fmt.tprintf("%s - %d fps", title, ork.get_fps_smoothed()))
}

