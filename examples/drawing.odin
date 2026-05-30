package examples

import "core:math"
import "core:fmt"

import ork "../"  // Ork itself

@(private="file") title := "Drawing Example (Ork)"
@(private="file") smiley: ork.Image


drawing_example_quit :: proc() {
	// nothing needed here
}


drawing_example_init :: proc() {
	smiley = ork.new_image("assets/smiley.png")
}


drawing_example_update :: proc() {
	ork.clear_cells(ex_console)  // clearing is optional
	{
		x, y, w, h := 7, 5, 5, 5
		r := 2  // radius

		ork.draw_text(ex_console, x-1, y-2, "Shapes", UI_HEADER_COL)

		ork.draw_rect(ex_console,    false,  x,        y,       w,  h, nil, nil, ork.GREEN7)
		ork.draw_rect(ex_console,    true,   x+w+2,    y,       w,  h, nil, nil, ork.GREEN7)
		ork.draw_circle(ex_console,  false,  x+r,      y+h+3,   r,     nil, nil, ork.DBLUE7)
		ork.draw_circle(ex_console,  true,   x+w+2+r,  y+h+3,   r,     nil, nil, ork.DBLUE7)
		ork.draw_line(ex_console,            x, y+h*2+4,  x+w*2+1, y+h*3+4, nil, nil, ork.GREEN7)

		ork.draw_text(ex_console, 28, y-2, "Images", UI_HEADER_COL)
		ork.draw_image(ex_console, 30, 5, 64, smiley, ork.AMBER6 )
		ork.draw_image(ex_console, 40, 5, smiley, ork.AMBER6 )

		tile1 := ork.index_to_char(ex_console, 5)
		tile2 := ork.index_to_char(ex_console, 14)
		tile3 := ork.index_to_char(ex_console, 176)
		text := fmt.tprintf("sèxÿ utf-8 téxt (cp437) wîth ascii tiles %r%r%r", tile1, tile2, tile3)
		ork.draw_text(ex_console, x, y+30, text, ork.Color{0, 255, 0, 255})
	}

	ork.set_window_title(fmt.tprintf("%s - %d fps", title, ork.get_fps_smoothed()))
}


drawing_example_render :: proc() {
	ork.render(ex_console)
}
