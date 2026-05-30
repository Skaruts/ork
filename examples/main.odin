#+feature dynamic-literals
package examples

import "core:fmt"
import "core:math"
import "core:slice"

import ork "../"  // Ork itself


ProcGroup :: struct {
	init   : proc(),
	update : proc(),
	render : proc(),
	quit   : proc(),
}

examples := map[string]ProcGroup {
	"Drawing"   = ProcGroup{ drawing_example_init, drawing_example_update, drawing_example_render, drawing_example_quit },
	"FOVs"      = ProcGroup{ fovs_example_init, fovs_example_update, fovs_example_render, fovs_example_quit },
	"AStar"     = ProcGroup{ astar_example_init, astar_example_update, astar_example_render, astar_example_quit },
	"Dijkstra"  = ProcGroup{ dij_example_init, dij_example_update, dij_example_render, dij_example_quit },
	"Camera"    = ProcGroup{ camera_example_init, camera_example_update, camera_example_render, camera_example_quit },
	"REXPaint"  = ProcGroup{ rexpaint_example_init, rexpaint_example_update, rexpaint_example_render, rexpaint_example_quit },
	"Noise"     = ProcGroup{ noise_example_init, noise_example_update, noise_example_render, noise_example_quit },
}
keys: []string

curr_example : int  = 0
in_menu      : bool = true

ui_console : ^ork.Console
ex_console : ^ork.Console
fonts      : [4]^ork.Font
curr_font  : = len(fonts)-1

WINDOW_TITLE :: "Ork Examples"

main :: proc() {
	ork.start(init, tick, quit)
}


init :: proc() {
	ork.set_panic_key(.None)
	ork.set_window_title(WINDOW_TITLE)

	// You can bind input actions to keys/combos, and you can use the same key
	// on multiple actions. E.g. for diagonal movement with numpad keys:
	ork.add_binds( "move_left",  { .A, .Left,  .NP_4, .NP_7, .NP_1 } )
	ork.add_binds( "move_right", { .D, .Right, .NP_6, .NP_9, .NP_3 } )
	ork.add_binds( "move_up",    { .W, .Up,    .NP_8, .NP_7, .NP_9 } )
	ork.add_binds( "move_down",  { .S, .Down,  .NP_2, .NP_1, .NP_3 } )

	ork.add_binds("prev_font", { .Comma,  .Page_Up })
	ork.add_binds("next_font", { .Period, .Page_Down })

	// The first parameter to `new_font` (`name`) can be ommited when not needed.
	// In this case I give them names so I can display them in the UI.
	fonts = {
		ork.new_font("cp437_8x8",   "assets/fonts/cp437_8x8.png"),
		ork.new_font("cp437_12x12", "assets/fonts/cp437_12x12.png"),
		ork.new_font("cp437_16x16", "assets/fonts/cp437_16x16.png"),
		ork.new_font("cp437_20x20", "assets/fonts/cp437_20x20.png"),
	}

	ui_console = ork.new_console(MAIN_GW, MAIN_GH, fonts[curr_font])
	ex_console = ork.new_console(GW, GH, fonts[curr_font])

	// You can set the position of a console. This will move it by steps
	// of its own cell size on the screen.
	ex_console.x = UI_WIDTH+1


	ks, _ := slice.map_keys(examples)
	keys = ks
	slice.sort(keys)
	for key in keys {
		examples[key].init()
	}
}


tick :: proc() {
	if ork.action_pressed("next_font") do next_font()
	if ork.action_pressed("prev_font") do prev_font()

	tick_menu()
	tick_example()
	should_redraw = false

	ork.render(ui_console)
}


quit :: proc() {
	for key in keys {
		examples[key].quit()
	}
	delete(keys)
}


next_font :: proc() {
	curr_font = int(math.wrap(f32(curr_font+1), f32(len(fonts))))
	ork.set_font(ui_console, fonts[curr_font])
	ork.set_font(ex_console, fonts[curr_font])
	noise_example_on_switch_font()
}


prev_font :: proc() {
	curr_font = int(math.wrap(f32(curr_font-1), f32(len(fonts))))
	ork.set_font(ui_console, fonts[curr_font])
	ork.set_font(ex_console, fonts[curr_font])
	noise_example_on_switch_font()
}


tick_example :: proc() {
	if !in_menu {
		if ork.key_pressed({.Escape}) {
			in_menu = true
		}
	}

	if !in_menu || should_redraw || player_moved {
		examples[keys[curr_example]].update()
	}

	examples[keys[curr_example]].render()
}


tick_menu :: proc() {
	if in_menu {
		if ork.key_pressed({.Escape}) {
			ork.exit()
		}
		if ork.key_pressed({.Enter}) {
			in_menu = false
		}

		if ork.key_repeat({.Up}) {
			curr_example = int(math.wrap(f32(curr_example-1), f32(len(keys))))
			should_redraw = true
		}
		if ork.key_repeat({.Down}) {
			curr_example = int(math.wrap(f32(curr_example+1), f32(len(keys))))
			should_redraw = true
		}
	}

	ork.set_clipping_area(ui_console, ork.Rect{0, 0, UI_WIDTH+1, MAIN_GH})
	{
		ork.clear_cells(ui_console)
		ui_separator_v(UI_WIDTH, 1, MAIN_GH-2)

		ui_y = 1
		y := ui_y
		ui_header(1, y, "Examples")
		ui_text(1, y+1, "(Enter/Escape)", UI_TEXT_PARENTESES)
		ui_list(2, y+3, 12, curr_example, keys, in_menu)

		y += len(keys)+4

		ui_separator_h(1, y+1, UI_WIDTH-3)

		y += 3
		ui_header(1, y, "Font")
		ui_text(1, y+1, "(pg_up/dn ,/.)", UI_TEXT_PARENTESES)
		ui_text(2, y+3, fonts[curr_font].name, UI_TEXT_COL)

		ui_y = y+6
	}
	ork.set_clipping_area(ui_console, nil)
}

