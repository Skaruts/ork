package examples

import "core:math"
import "core:fmt"

import ork "../"  // Ork itself
import "../libs/ui"


@(private="file") title := "FOV Example (Ork)"
@(private="file") gmap  : GameMap

@(private="file") player := Entity { {}, '@', ork.AMBER7, ork.BLACK }

@(private="file") MAX_FOV_RANGE :: 100
@(private="file") fov_names : [len(ork.FovType)]string
@(private="file") curr_fov  := ork.FovType.Restrictive

@(private="file") fov_light_walls := true

@(private="file") theme := 0


@(private="file") _draw_ui :: proc() {
	y := ui.next_y()

	ui.container("FOV", {0, y, UI_WIDTH+1, MAIN_GH-y}); {
		y = 2
		ui.text({1, y}, "FOVs", ork.GREEN4)
		ui.text({ui.next_x()+1, y}, "(home/end)", UI_TEXT_HOTKEYS)

		ui_selector({2, ui.next_y(2)}, int(curr_fov), fov_names[:])

		y = ui.next_y(2)
		ui.text({1, y}, "Vis", ork.GREEN4)
		ui.text({ui.next_x()+1, y}, "(ins/del)", UI_TEXT_HOTKEYS)

		radius := fov_radius
		if ui.spinner({2, ui.next_y(2)}, 3, "Radius", &radius, 1, MAX_FOV_RANGE, 1).value_changed {
			set_fov_range(radius - fov_radius)
		}
	}
	ui.end_container()
}


switch_fov :: proc(dir: int) {
	if dir == 0 do return
	curr_fov = ork.FovType( math.wrap(f32(int(curr_fov) + dir), f32(len(ork.FovType))) )
	should_redraw = true
}


set_fov_range :: proc(dir: int) {
	if dir == 0 do return
	fov_radius = math.clamp(fov_radius+dir, 1, MAX_FOV_RANGE)
	should_redraw = true
}




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
	gmap.map_type = MapType.Dungeon

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
	if      ork.mouse_down({.MouseLeft})  do paint_tile(&gmap, .Wall)
	else if ork.mouse_down({.MouseRight}) do paint_tile(&gmap, .Floor)

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
	_draw_ui()

	if !in_menu {
		_handle_input()

		dir := ork.Vec2{}
		if ork.action_repeat("move_left")  do dir.x -= 1
		if ork.action_repeat("move_right") do dir.x += 1
		if ork.action_repeat("move_up")    do dir.y -= 1
		if ork.action_repeat("move_down")  do dir.y += 1

		if dir != ork.VEC2_ZERO {
			player_moved = try_move(gmap, &player, dir.x, dir.y)
		}
	}

	if !player_moved && !should_redraw do return

	ork.clear_cells(ex_console)
	ork.fov_compute(gmap.fovmap, player.pos, fov_radius, curr_fov, fov_light_walls)
	draw_tiles_fov(ex_console, &gmap)
	ork.draw_cell(ex_console, player.x, player.y, player.glyph, player.fg, player.bg)

	player_moved = false
}


fovs_example_render :: proc() {
	ork.render(ex_console)
}

