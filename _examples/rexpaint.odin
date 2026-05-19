#+feature dynamic-literals
package examples

import "core:fmt"
import ork "../"  // Ork itself


@(private="file") title      := "REXPaint Example (Orc)"
@(private="file") gmap       : GameMap
@(private="file") cam        : ^ork.Camera
@(private="file") player     := Entity { {}, '@', ork.AMBER7, ork.BLACK }
@(private="file") fov_radius := 20


_init_map_rex :: proc(xp_file_path: string, gmap: ^GameMap, player: ^Entity = nil) {
	rex_img := ork.rex_load_image(xp_file_path)
	defer ork.rex_delete_image(rex_img)

	gmap.w = rex_img.w
	gmap.h = rex_img.h

	gmap.tiles = make([]Tile, gmap.w*gmap.h)
	gmap.fovmap = ork.new_fov(gmap.w, gmap.h)

	GROUND_LAYER :: 1
	WALL_LAYER   :: 2
	PLAYER_LAYER :: 3

	TREE_IDX     :: int(6)

	for j in 0 ..< gmap.h {
		for i in 0 ..< gmap.w {
			ground_cell := ork.rex_get_cell(rex_img, GROUND_LAYER, i, j)
			wall_cell   := ork.rex_get_cell(rex_img, WALL_LAYER,   i, j)

			idx := i+j*gmap.w

			if !ork.rex_is_transparent(rex_img, ground_cell) {
				char      := ork.index_to_char(ex_console, ork.Index(ground_cell.glyph))
				fg        := transmute(ork.Color)(ground_cell.fg)
				bg        := transmute(ork.Color)(ground_cell.bg)
				is_floor  := ground_cell.glyph != TREE_IDX
				tile_type := is_floor ? TileType.Floor : TileType.Wall

				gmap.tiles[idx] = new_tile(tile_type, char, fg, bg, is_floor, is_floor)
			}

			if !ork.rex_is_transparent(rex_img, wall_cell) {
				char := ork.index_to_char(ex_console, ork.Index(wall_cell.glyph))
				fg   := transmute(ork.Color)(wall_cell.fg)
				bg   := transmute(ork.Color)(wall_cell.bg)

				if ork.Index(wall_cell.glyph) == LINE_H || ork.Index(wall_cell.glyph) == LINE_V {
					gmap.tiles[idx] = new_tile(TileType.Wall, char, fg, bg, false, true)
				} else {
					gmap.tiles[idx] = new_tile(TileType.Wall, char, fg, bg, false, false)
				}
			}

			for idx in 0 ..< gmap.w*gmap.h {
				i     := idx % gmap.w
				j     := idx / gmap.w
				glyph := ork.rex_get_glyph(rex_img, PLAYER_LAYER, i, j)

				if glyph == 64 {
					player.pos = ork.Vec2{i, j}
					break
				}
			}
		}
	}

	init_fov(gmap)
}


rexpaint_example_init :: proc() {
	_init_map_rex("assets/rex_forest.xp", &gmap, &player)

	cam = ork.new_camera(0, 0, GW, GH)
	ork.camera_set_position(cam, player.pos)
}


rexpaint_example_update :: proc() {
	if !in_menu {
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
	ork.fov_compute(gmap.fovmap, player.pos, fov_radius, .Restrictive)

	ork.camera_set_position(cam, player.pos)
	ork.begin_camera(cam)
	{
		draw_tiles_fov_cam(ex_console, &gmap, cam)
		ork.draw_cell(ex_console, player.pos.x, player.pos.y, player.glyph, player.fg, player.bg)
	}
	ork.end_camera()

	player_moved = false
	should_redraw = false
}


rexpaint_example_render :: proc() {
	ork.render(ex_console)
}


rexpaint_example_quit :: proc() {
	delete(gmap.tiles)
}

