package examples

import "core:strings"
import "core:fmt"
import ork "../"  // Ork itself


MAIN_GW :: 80  // main console grid width/height
MAIN_GH :: 45

UI_WIDTH :: 18
GW :: MAIN_GW - UI_WIDTH-1   // grid dimensions used by the examples
GH :: MAIN_GH


LINE_H :: ork.Index(196)  // Assuming cp437 is being used.
LINE_V :: ork.Index(179)  // Index needs to be typed, or the drawing procs will take it as a rune.


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

MapType :: enum {
	Empty,
	Dungeon,
	Caves,
	Drunk_Walk,
	BSP,
}

fov_radius          : = 20
tile_darken_percent : = 0.7
show_fog_of_war     : = true

should_redraw : bool = true
player_moved  : bool

floor_tile := new_tile(.Floor, 0, {}, ork.BROWN2, true, true)
wall_tile  := new_tile(.Wall, '#', ork.GRAY4, ork.BLACK, false, false)



new_tile :: proc {
	new_tile_from_tile,
	new_tile_from_data,
}

new_tile_from_tile :: proc "contextless" (t: Tile) -> Tile {
	return new_tile_from_data(t.type, t.glyph, t.fg, t.bg, t.walkable, t.transparent)
}

new_tile_from_data :: proc "contextless" (type: TileType, glyph: ork.Rune, fg, bg: ork.Color,
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


// This allows sliding along the walls. May not be so ideal
// for real games, but it's great for testing.
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


init_map :: proc(w, h: int, gmap: ^GameMap, player: ^Entity = nil) {
	// delete map if it's been initialized before
	delete(gmap.tiles)
	ork.delete_mapgen(gmap.mapgen)

	gmap.w = w
	gmap.h = h

	mapgen := ork.new_mapgen(w, h)
	gmap.mapgen = mapgen

	pos: ork.Vec2
	#partial switch gmap.map_type {
		case .Empty:      pos = ork.mapgen_create_empty(mapgen, 0.99)
		case .Dungeon:    pos = ork.mapgen_create_simple_dungeon(mapgen, 15, 5, 10)
		case .Caves:      pos = ork.mapgen_create_caves(mapgen, 0.6, 4, 3, 6)
		case .Drunk_Walk: pos = ork.mapgen_create_drunk_caves(mapgen, 10, 200)
		case .BSP:        pos = ork.mapgen_create_bsp_dungeon(mapgen, ork.BSP_Config{8, 1, 1, 5, 10, 5, 10})
	}

	if player != nil {
		player.pos = pos
	}

	gmap.tiles  = make([]Tile, w*h)
	if gmap.fovmap == nil {
		gmap.fovmap = ork.new_fov(w, h)
	}

	for j in 0 ..< h {
		for i in 0 ..< w {
			idx := i+j*w
			if mapgen.cells[idx] == mapgen.floor_id {
				gmap.tiles[idx] = new_tile(floor_tile)
			} else {
				gmap.tiles[idx] = new_tile(wall_tile)
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


paint_tile :: proc(gmap: ^GameMap, tile_type: TileType) {
	mouse := ork.get_mouse_position(ex_console)
	mx, my := mouse.x, mouse.y

	// don't allow removing the edges, to prevent crashes
	if mx < 1 || mx >= gmap.w-1 || my < 1 || my >= gmap.h-1 do return

	idx := mx+my*gmap.w
	if tile_type == gmap.tiles[idx].type do return
	gmap.tiles[idx] = tile_type == .Wall  \
	                ? new_tile(wall_tile) \
	                : new_tile(floor_tile)


	tile := gmap.tiles[idx]
	ork.fov_set_cell(gmap.fovmap, mx, my, tile.transparent, tile.walkable)
	should_redraw = true
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
			}
		}
	}
}



/********************************************
	Some UI helpers
*/

UI_SEP_COL            :: ork.GRAY1
UI_HEADER_COL         :: ork.GREEN4
UI_TEXT_COL           :: ork.GRAY6
UI_TEXT_FADED_COL     :: ork.GRAY4
UI_SELECTED_COL       :: ork.BLUE3
UI_SELECTED_FADED_COL :: ork.GRAY2
UI_DIGIT              :: ork.Color{150, 0, 255, 255}
UI_TEXT_SELECTED_COL  :: ork.AMBER5
UI_TEXT_PARENTESES    :: ork.GRAY1

ui_y := 1


ui_text :: proc(x, y: int, text: string, fg: ork.Color, bg: Maybe(ork.Color)=nil) {
	ork.draw_text(ui_console, x, y, text, fg, bg)
}

ui_header :: proc(x, y: int, text: string) {
	ork.draw_text(ui_console, x, y, text, UI_HEADER_COL)
}

ui_separator_v :: proc(x, y, length: int) {
	ork.draw_line(ui_console, x, y, x, y+length, LINE_V, UI_SEP_COL)
}

ui_separator_h :: proc(x, y, length: int) {
	ork.draw_line(ui_console, x, y, x+length, y, LINE_H, UI_SEP_COL)
}


ui_list :: proc(x, y, w, selected: int, items: []string, active: bool) {
	for text, i in items {
		fg := i == selected ? UI_TEXT_COL : UI_TEXT_FADED_COL
		bg := active \
			? i == selected ? UI_SELECTED_COL       : ork.BLACK \
			: i == selected ? UI_SELECTED_FADED_COL : ork.BLACK

		yi := y+i
		ork.draw_line(ui_console, x, yi, w, yi, nil, nil, bg)
		ork.draw_text(ui_console, x+1, yi, text, fg)
	}
}


ui_selector :: proc(x, y, selected_idx: int, options: []string) {
	for opt_name, i in options {
		fg := UI_TEXT_FADED_COL

		if i == selected_idx {
			fg = UI_TEXT_SELECTED_COL
			ork.draw_cell(ui_console, x, y+i, ork.Index(16), UI_TEXT_SELECTED_COL, ork.BLACK)
		}

		ork.draw_text(ui_console, x+2, y+i, opt_name, fg, ork.BLACK)
	}
}

ui_is_under_mouse :: proc(x, y, w, h: int) -> bool {
	mp := ork.get_mouse_position(ui_console)
	return mp.x >= x && mp.x < x+w \
	    && mp.y >= y && mp.y < y+h
}

ui_icon_button :: proc(x, y: int, icon: ork.Index) -> bool {
	hovered := ui_is_under_mouse(x, y, 1, 1)
	pressed := hovered && ork.mouse_down({.MouseLeft})

	fg := ork.GRAY4
	if      pressed do fg = ork.GRAY8
	else if hovered do fg = ork.GRAY6
	ork.draw_cell(ui_console, x, y, icon, fg)

	return pressed
}

ui_spinner :: proc(x, y, w: int, text: string, value: ^int, lo, hi, step: int) -> bool {
	old_value := value^
	tlen := ork.string_len(text)

	// max width of digits in runes
	nw := max(4, ork.string_len( fmt.tprintf("%d", lo < 0 ? lo : hi) ))

	rb_x := x+w
	nx   := x+w-nw
	lb_x := nx-1

	lpressed := ui_icon_button(lb_x, y, ork.Index(17))
	rpressed := ui_icon_button(rb_x, y, ork.Index(16))
	repeat   := (lpressed || rpressed) && ork.mouse_repeat({.MouseLeft})

	if repeat {
		if lpressed do value^ = max(lo, value^-step)
		if rpressed do value^ = min(hi, value^+step)
	}

	ork.draw_text(ui_console, x, y, text, UI_TEXT_COL)

	digit_text := strings.right_justify(fmt.tprintf("%d", value^), nw, " ", context.temp_allocator)
	ork.draw_text(ui_console, nx, y, digit_text, UI_DIGIT)

	return value^ != old_value
}

ui_spinnerf :: proc(x, y, w: int, text: string, value: ^f32, lo, hi, step: f32) -> bool {
	old_value := value^
	tlen := ork.string_len(text)

	// max width of digits in runes
	nw := max(4, ork.string_len( fmt.tprintf("%.2f", lo < 0 ? lo : hi) ))

	rb_x := x+w
	nx   := x+w-nw
	lb_x := nx-1

	lpressed := ui_icon_button(lb_x, y, ork.Index(17))
	rpressed := ui_icon_button(rb_x, y, ork.Index(16))
	repeat := (lpressed || rpressed) && ork.mouse_repeat({.MouseLeft})

	if repeat {
		if lpressed do value^ = max(lo, value^-step)
		if rpressed do value^ = min(hi, value^+step)
	}

	ork.draw_text(ui_console, x, y, text, UI_TEXT_COL)

	digit_text := strings.right_justify(fmt.tprintf("%.2f", value^), nw, " ", context.temp_allocator)
	ork.draw_text(ui_console, nx, y, digit_text, UI_DIGIT)

	return value^ != old_value
}
