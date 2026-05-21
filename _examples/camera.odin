#+feature dynamic-literals
package examples

import "core:fmt"
import "core:math"
import ork "../"  // Ork itself


@(private="file") title      := "REXPaint Example (Ork)"
@(private="file") gmap       : GameMap
@(private="file") cam        : ^ork.Camera
@(private="file") player     := Entity { {}, '@', ork.AMBER7, ork.BLACK }
@(private="file") enemy      := Entity { {}, 'E', ork.BLUE7,  ork.BLACK }
@(private="file") fov_radius := 20
@(private="file") entities: [dynamic]Entity

@(private="file") MW, MH := 100, 100  // map size


@(private="file")
_draw_entities :: proc(console: ^ork.Console, gmap: ^GameMap, \
                       entities: []Entity,    cam: ^ork.Camera) {

	// To render entities with a camera, convert their positions to
	// screen positions, and check if they're in view. Then check if the
	// world position is visible.

	for e in entities {
		x, y := e.pos.x, e.pos.y

		// TODO: the entire API is inconsistent in how it handles coordinates
		sx, sy := ork.camera_to_screen(cam, x, y)
		if !ork.camera_is_in_viewport(cam, sx, sy) do continue

		in_fov := ork.fov_is_visible(gmap.fovmap, x, y)

		if in_fov || !show_fog_of_war {
			ork.draw_cell(console, x, y, e.glyph, e.fg, e.bg)
		}
	}
}

camera_example_init :: proc() {
	gmap.map_type = MapType.Caves

	init_map(MW, MH, &gmap, &player)  // the fov is initialized in 'init_map'

	for i in 0 ..< 30 {
		rat := Entity { {}, 'r', ork.GRAY5,  ork.BLACK }
		init_enemy(&rat, &gmap)
		append(&entities, rat)
	}

	// The dimensions passed to the camera are its viewport size. In this case
	// it's the size of the example's part of the screen (excluding the UI).
	// Since the 'ex_console' itself was moved in init, the viewport's x and y
	// can be zero.
	cam = ork.new_camera(0, 0, GW, GH)
	ork.camera_set_position(cam, player.pos)
}


camera_example_update :: proc() {
	if !in_menu {
		dir := ork.Vec2{}
		if ork.action_repeat("move_left")  do dir.x -= 1
		if ork.action_repeat("move_right") do dir.x += 1
		if ork.action_repeat("move_up")    do dir.y -= 1
		if ork.action_repeat("move_down")  do dir.y += 1

		if dir != ork.VEC2_ZERO {
		 	player_moved = try_move(gmap, &player, dir.x, dir.y)
		}

		if ork.key_pressed({.Space}) {
			gmap.map_type = MapType(math.wrap(f32(gmap.map_type)+1, len(MapType)))
			init_map(MW, MH, &gmap, &player)
			for &e in entities {
				init_enemy(&e, &gmap)
			}
			should_redraw = true
		}
	}

	if !player_moved && !should_redraw do return

	for &e in entities {
		dx := ork.randi(-1, 2)  // upper limit is exclusive
		dy := ork.randi(-1, 2)
		try_move(gmap, &e, dx, dy)
	}

	ork.clear_cells(ex_console)
	ork.fov_compute(gmap.fovmap, player.pos, fov_radius, .Restrictive)

	// Update the position of the camera whenever the player moves
	ork.camera_set_position(cam, player.pos)

	// this tells Ork to draw everything transformed to this camera
	ork.begin_camera(cam)
	{
		draw_tiles_fov_cam(ex_console, &gmap, cam)
		ork.draw_cell(ex_console, player.pos.x, player.pos.y, player.glyph, player.fg, player.bg)

		_draw_entities(ex_console, &gmap, entities[:], cam)
	}
	ork.end_camera()    // Reset back to "no-camera"


	player_moved = false
	should_redraw = false
}


camera_example_render :: proc() {
	ork.render(ex_console)
}


camera_example_quit :: proc() {
	delete(gmap.tiles)
	delete(entities)
}

