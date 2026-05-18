package examples

import ork "../"  // Ork itself


MAIN_GW :: 80  // main console grid width/height
MAIN_GH :: 45

UI_WIDTH :: 15
GW :: MAIN_GW - UI_WIDTH-1   // grid dimensions used by the examples
GH :: MAIN_GH


LINE_H :: ork.Index(196)  // Assuming cp437 is being used.
LINE_V :: ork.Index(179)  // Index needs to be typed, or the drawing procs will take it as a rune.

UI_SEP_COL            :: ork.GRAY1
UI_HEADER_COL         :: ork.GREEN4
UI_TEXT_COL           :: ork.GRAY6
UI_TEXT_FADED_COL     :: ork.GRAY4
UI_SELECTED_COL       :: ork.BLUE3
UI_SELECTED_FADED_COL :: ork.GRAY2


TileType :: enum { Floor, Wall, Water }

Tile :: struct {
	type        : TileType,
	glyph       : ork.Rune,
	fg, bg      : ork.Color,
	walkable    : bool,
	transparent : bool,
	explored    : bool,
}

GameMap :: struct {
	w, h   : int,
	tiles  : []Tile,
	fovmap : ^ork.Fovmap,
	mapgen : ^ork.MapGen,
	map_type: MapType,
}

Entity :: struct {
	pos    : ork.Vec2,
	glyph  : ork.Rune,
	fg, bg : ork.Color,
}

fov_radius          : = 20
tile_darken_percent : = 0.7
show_fog_of_war     : = true

should_redraw : bool = true
player_moved  : bool



new_tile :: proc {
	new_tile_from_tile,
	new_tile_from_data,
}

new_tile_from_tile :: proc(t: Tile) -> Tile {
	return new_tile_from_data(t.type, t.glyph, t.fg, t.bg, t.walkable, t.transparent)
}

new_tile_from_data :: proc(type: TileType, glyph: ork.Rune, fg, bg: ork.Color,
				walkable, transparent:bool) -> Tile {
	return Tile {
		type        = type,
		glyph       = glyph,
		fg          = fg,
		bg          = bg,
		walkable    = walkable,
		transparent = transparent,
		explored    = false,
	}
}


// this allows sliding along the walls
try_move :: proc(gmap: GameMap, ent: ^Entity, dx, dy: int) -> bool {
	dx, dy := dx, dy
	pos := &ent.pos
	tx :=  pos.x + dx
	ty :=  pos.y + dy

	if tx < 0 || tx >= gmap.w do dx = 0
	if ty < 0 || ty >= gmap.h do dy = 0

	if dx != 0 && dy != 0 && gmap.tiles[tx+ty*gmap.w].walkable {
		pos.x = tx
		pos.y = ty
		return true
	}
	if dx != 0 && gmap.tiles[tx+pos.y*gmap.w].walkable {
		pos.x = tx
		return true
	}
	if dy != 0 && gmap.tiles[pos.x+ty*gmap.w].walkable {
		pos.y = ty
		return true
	}
	return false
}

MapType :: enum {
	Empty,
	Dungeon,
	Caves,
	Drunk_Walk,
}


init_map :: proc(w, h: int, gmap: ^GameMap, player: ^Entity = nil) {
	// delete map if it's been initialized before
	delete(gmap.tiles)
	// ork.delete_fov(gmap.fovmap)
	ork.delete_mapgen(gmap.mapgen)

	gmap.w = w
	gmap.h = h

	mapgen := ork.new_mapgen(w, h)
	gmap.mapgen = mapgen

	pos: ork.Vec2
	switch gmap.map_type {
		case .Empty:      pos = ork.mapgen_create_empty(mapgen, 0.99)
		case .Dungeon:    pos = ork.mapgen_create_simple_dungeon(mapgen, 15, 5, 10)
		case .Caves:      pos = ork.mapgen_create_caves(mapgen, 0.6, 4, 3, 6)
		case .Drunk_Walk: pos = ork.mapgen_create_drunk_caves(mapgen, 10, 200)
	}

	if player != nil {
		player.pos = pos
	}

	gmap.tiles  = make([]Tile, w*h)
	if gmap.fovmap == nil {
		gmap.fovmap = ork.new_fov(w, h)
	}

	block := ork.index_to_char(ex_console, 219)

	for j in 0 ..< h {
		for i in 0 ..< w {
			idx := i+j*w
			if mapgen.cells[idx] == mapgen.floor_id {
				gmap.tiles[idx] = new_tile(TileType.Floor, 0, {}, ork.BROWN3, true, true)
			} else {
				gmap.tiles[idx] = new_tile(TileType.Wall, block, ork.BROWN6, ork.BLACK, false, false)
			}
		}
	}

	init_fov(gmap)
}


init_fov :: proc(gmap: ^GameMap) {
	ork.fov_clear(gmap.fovmap)
	for i in 0 ..< gmap.h*gmap.w {
		tile := gmap.tiles[i]
		ork.fov_set_cell(gmap.fovmap, int(i%gmap.w), i/gmap.w, tile.transparent, tile.walkable)
	}
}

init_enemy :: proc(enemy: ^Entity, gmap: ^GameMap) {
	#partial switch gmap.map_type {
		case .Dungeon:
			pos, _ := ork.mapgen_get_position_in_room(gmap.mapgen)
			enemy.pos = pos
		case:
			enemy.pos = ork.mapgen_get_random_position_attempts(gmap.mapgen)
	}
}


draw_tiles :: proc(gmap: ^GameMap) {
	for j in 0 ..< GH {
		for i in 0 ..< GW {
			tile := gmap.tiles[i+j*gmap.w]
			ork.draw_cell(ex_console, i, j, tile.glyph, tile.fg, tile.bg)
		}
	}
}

draw_tiles_fov :: proc(console: ^ork.Console, gmap: ^GameMap) {
	for j in 0 ..< gmap.h {
		for i in 0 ..< gmap.w {
			tile := &gmap.tiles[i+j*gmap.w]
			in_fov := ork.fov_is_visible(gmap.fovmap, i, j)

			if in_fov || !show_fog_of_war {
				if !tile.explored && in_fov do tile.explored = true
				ork.draw_cell(console, i, j, tile.glyph, tile.fg, tile.bg)
			} else if tile.explored {
				fg := ork.color_darkened(tile.fg, tile_darken_percent)
				bg := ork.color_darkened(tile.bg, tile_darken_percent)
				ork.draw_cell(console, i, j, tile.glyph, fg, bg)
			}
		}
	}
}

draw_tiles_fov_cam :: proc(console: ^ork.Console, gmap: ^GameMap, cam: ^ork.Camera, ) {
	rect := ork.camera_get_visible_world_rect(cam)

	l := max(rect.x, 0)
	r := min(gmap.w, rect.x+rect.w)
	t := max(rect.y, 0)
	b := min(gmap.h, rect.y+rect.h)

	for j in t ..< b {
		for i in l ..< r {
			tile := &gmap.tiles[i+j*gmap.w]
			in_fov := ork.fov_is_visible(gmap.fovmap, i, j)

			if in_fov || !show_fog_of_war {
				if !tile.explored && in_fov do tile.explored = true
				ork.draw_cell(console, i, j, tile.glyph, tile.fg, tile.bg)
			} else if tile.explored {
				fg := ork.color_darkened(tile.fg, tile_darken_percent)
				bg := ork.color_darkened(tile.bg, tile_darken_percent)
				ork.draw_cell(console, i, j, tile.glyph, fg, bg)
			// } else {
			// 	ork.draw_cell(console, i, j, nil, ork.BLACK, ork.BLACK)
			}
		}
	}
}
