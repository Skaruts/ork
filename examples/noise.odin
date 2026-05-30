#+feature dynamic-literals
package examples

import "core:time"
import "core:math/noise"
import "core:fmt"
import "core:math"
import ork "../"  // Ork itself


@(private="file") title      := "REXPaint Example (Ork)"
// @(private="file") gmap       : GameMap
@(private="file") con_scale := 4
@(private="file") MW, MH := GW*con_scale, GH*con_scale  // map size
@(private="file") noise_con : ^ork.Console

seed        : i64 = 0
scale       : int = 50
octaves     : int = 4
persistence : f32 = 0.35
lacunarity  : f32 = 2.5

snow        : f32 = 0.90
mountain    : f32 = 0.75
grass       : f32 = 0.55
beach       : f32 = 0.5
water       : f32 = 0.2



noise_example_on_switch_font :: proc() {
	// This is just so ensure the noise console keeps the correct size,
	// independently from whatever font is being used
	cw, ch := ork.get_cell_size(ex_console)
	ork.set_cell_size(noise_con, cw/con_scale, ch/con_scale)
	noise_con.x = (UI_WIDTH+1)*con_scale
}

noise_example_init :: proc() {
	noise_con = ork.new_console(MW, MH, fonts[0])
	noise_example_on_switch_font()
	_generate_noise()
}


@(private="file")
_generate_noise :: proc() {
	noise := ork.new_noise_map_2d(MW, MH, f32(scale), octaves, persistence, lacunarity)
	defer ork.delete_noise_map_2d(noise)

	// Painting the noise directly to a console just as an example.
	// In a real use-case this might be turned into map tiles instead
	for j in 0 ..< MH {
		for i in 0 ..< MW {
			idx := i+j*MW

			col: ork.Color
			if      noise[idx] > snow     do col = ork.GRAY8
			else if noise[idx] > mountain do col = ork.BROWN2
			else if noise[idx] > grass    do col = ork.GREEN3
			else if noise[idx] > beach    do col = ork.BROWN8
			else if noise[idx] > water    do col = ork.BLUE6
			else                          do col = ork.BLUE1

			ork.draw_bg(noise_con, i, j, col)
		}
	}
}

@(private="file") _draw_ui :: proc() {
	x, y := 1, ui_y
	ui_separator_h(x, y, UI_WIDTH-3)

	y += 2
	ui_header(x, y, "Noise")

	y += 2
	if ui_spinner( x+1, y,   14, "Scale",   &scale,       1, 200,    1) do _generate_noise()
	if ui_spinner( x+1, y+1, 14, "Octaves", &octaves,     1,  16,    1) do _generate_noise()
	if ui_spinnerf(x+1, y+2, 14, "Persist", &persistence, 0,   9, 0.05) do _generate_noise()
	if ui_spinnerf(x+1, y+3, 14, "Lacunar", &lacunarity,  0,   9, 0.05) do _generate_noise()

	y += 5
	ui_header(x, y, "Terrain")

	y += 2
	if ui_spinnerf(x+1, y,   14, "Snow",     &snow,     0, 1,        0.05) do _generate_noise()
	if ui_spinnerf(x+1, y+1, 14, "Mountain", &mountain, 0, snow,     0.05) do _generate_noise()
	if ui_spinnerf(x+1, y+2, 14, "Grass",    &grass,    0, mountain, 0.05) do _generate_noise()
	if ui_spinnerf(x+1, y+3, 14, "Beach",    &beach,    0, grass,    0.05) do _generate_noise()
	if ui_spinnerf(x+1, y+4, 14, "Water",    &water,    0, beach,    0.05) do _generate_noise()
}

noise_example_update :: proc() {
	if in_menu do return

	if ork.key_pressed({.Space}) {
		seed := u64(time.time_to_unix_nano(time.now()))
		ork.print(seed)
		ork.set_seed(seed)
		_generate_noise()
		should_redraw = true
	}

	_draw_ui()
}


noise_example_render :: proc() {
	ork.render(noise_con)
}


noise_example_quit :: proc() {

}

