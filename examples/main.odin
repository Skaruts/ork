#+feature dynamic-literals
package examples

import "core:fmt"
import "core:math"
import "core:slice"

import ork "../"  // Ork itself
import "../libs/ui" // Ork UI


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
	// By default the exit key is Escape, but the examples need it
	ork.set_exit_key(.Null)

	// You can set a custom window title
	ork.set_window_title(WINDOW_TITLE)

	// You can bind input actions to keys/combos, and you can also use the
	// same key on multiple actions. E.g. for diagonal movement with keypad keys:
	ork.add_binds( "move_left",  { .A, .Left,  .KP_4, .KP_7, .KP_1 } )
	ork.add_binds( "move_right", { .D, .Right, .KP_6, .KP_9, .KP_3 } )
	ork.add_binds( "move_up",    { .W, .Up,    .KP_8, .KP_7, .KP_9 } )
	ork.add_binds( "move_down",  { .S, .Down,  .KP_2, .KP_1, .KP_3 } )

	ork.add_binds("prev_font", { .Comma,  .Page_Up })
	ork.add_binds("next_font", { .Period, .Page_Down })

	// If you need to add modifier keys (Ctrl, Shift, ALt), use this instead
	ork.add_bind_mod("example mod combo", {.C, {.Left_Control}})


	// The first parameter to `new_font` (`name`) can be ommited when not needed.
	// In this case we give them names so we can display them in the UI.
	fonts = {
		ork.new_font("cp437_8x8",   "assets/fonts/cp437_8x8.png"),
		ork.new_font("cp437_12x12", "assets/fonts/cp437_12x12.png"),
		ork.new_font("cp437_16x16", "assets/fonts/cp437_16x16.png"),
		ork.new_font("cp437_20x20", "assets/fonts/cp437_20x20.png"),
	}

	// At least one console must be created in `init`, as Ork determines the
	// window size based on the first console that gets created (the main console).
	ui_console = ork.new_console(MAIN_GW, MAIN_GH, fonts[curr_font])
	ex_console = ork.new_console(GW, GH, fonts[curr_font])

	// You can still set a different main console, if you need. Doing this
	// outside `init` may resize the window, if the new console's cell size
	// is different.
	ork.set_main_console(ui_console)

	// You can set the position of a console. This will move it by steps
	// of its own cell size on the screen.
	ex_console.x = UI_WIDTH+1

	// The UI must be initialized, and provided with a console
	ui.init(ui_console)

	init_custom_ui()  // see custom_ui.odin

	// This initializes each of the examples.
	ks, _ := slice.map_keys(examples)
	keys = ks
	slice.sort(keys)
	for key in keys {
		examples[key].init()
	}
}


tick :: proc() {
	// We need to let the UI prepare for the new frame.
	ui.begin_frame()

	if ork.action_pressed("next_font") do next_font()
	if ork.action_pressed("prev_font") do prev_font()

	tick_menu()
	tick_example()
	should_redraw = false

	// We also need to let the ui render and do internal updates.
	// The ui renders the ui_console internally.
	ui.end_frame()
}


quit :: proc() {
	// When done, tell the UI it can clean up and close.
	ui.close()

	// This closes up each of the examples.
	for key in keys {
		examples[key].quit()
	}
	delete(keys)
}


next_font :: proc() {
	// When switching fonts, we must update all the consoles that
	// need to be updated.
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

	// if !in_menu || should_redraw || player_moved {
	examples[keys[curr_example]].update()
	// }

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

	ui.container("Examples", {0, 0, UI_WIDTH+1, 12}); {
		ui.text({1, 1}, "(Enter/Escape)", UI_TEXT_HOTKEYS)
		ui_list(ui.next_y(2), 12, curr_example, keys, in_menu)
	}
	ui.end_container()

	nr := ui.next_row()
	ui.container("Font", {nr.x, nr.y, UI_WIDTH+1, 6}); {
		ui.text({1, 1}, "(pg_up/dn ,/.)", UI_TEXT_HOTKEYS)
		ui.text({2, 3}, fonts[curr_font].name)
	}
	ui.end_container()
}

