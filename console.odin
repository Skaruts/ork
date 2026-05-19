package ork

import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:unicode/utf8"
import "core:strings"

import k2 "libs/karl2d"



DEF_BG :: TRANSP
DEF_FG :: TRANSP
DEF_GLYPH :: 0

Rune :: distinct rune
Index :: distinct uint

Cell :: struct {
	glyph : Rune,
	fg    : Color,
	bg    : Color,
}

Cells :: struct {
	glyphs : []Index,
	fgs    : []Color,
	bgs    : []Color,
}


Batch_Rendering :: struct {
	verts    : []Vec2f,
	uvs      : []Vec2f,
	colors   : []Color,
	font_uvs : []Vec2f,
}

Texture_Rendering :: struct {
	rtex   : k2.Render_Texture,
}

Shader_Rendering :: struct {
	shader      : k2.Shader,
	shader_tex  : k2.Texture,
	fg_pixels   : []u8,
	char_pixels : []u8,
	fg_tex      : k2.Texture,
	char_tex    : k2.Texture,
}

Rendering :: union {
	Batch_Rendering,
	Texture_Rendering,
	Shader_Rendering,
}

Console :: struct {
	x, y            : int,
	w, h            : int,   // Do NOT change this (read only)
	tint            : Color,

	_font           : ^Font,
	_cw, _ch        : int,  // cell width / height
	_is_updated     : bool,
	_clip_area      : Rect,

	_arena          : virtual.Arena,
	_allocator      : mem.Allocator,
	_rend_arena     : virtual.Arena,
	_rend_allocator : mem.Allocator,

	_new_cells      : Cells,
	_cells          : Cells,

	_rendering      : Rendering,

	_bg_pixels      : []u8,
	_bg_tex         : k2.Texture,
	_main_rtex      : k2.Render_Texture,
}

// Creates a new console of `w` width and `h` height, with `font` font.
// Cell size overrides can be passed to `cw_ovr` and `ch_ovr`.
new_console :: proc(#any_int w, h: int, font: ^Font = nil,
                    cw_ovr: Maybe(int)=nil, ch_ovr: Maybe(int)=nil
                   ) -> ^Console {
	c := _create_console(w, h, font, cw_ovr, ch_ovr)
	append(&internal.consoles, c)

	if internal.main_console == nil {
		internal.main_console = c
		_resize_window()
	}

	return c
}


// Deletes a console and frees its memory. The pointer becomes invalid.
delete_console :: proc(c: ^Console, loc := #caller_location) {
	if c == nil do return
	if c == internal.main_console {
		__error_quit(msg="can't remove the main console without replacing it first.", loc=loc)
	}

	idx, ok := _get_item_index(internal.consoles[:], c)
	if ok do unordered_remove(&internal.consoles, idx)
	_free_console(c)
}


@private _create_console :: proc(#any_int w, h: int, font: ^Font = nil,
                        cw_ovr: Maybe(int)=nil, ch_ovr: Maybe(int)=nil,
                        loc := #caller_location
                    ) -> ^Console {
	c: ^Console = new(Console)
	c._allocator = virtual.arena_allocator(&c._arena)
	c._rend_allocator = virtual.arena_allocator(&c._rend_arena)

	if w == 0 || h == 0 {
		fmt.panicf("console dimensions cannot be zero", loc=loc)
	}

	c.w = w
	c.h = h
	c.tint = WHITE
	c._clip_area = {c.x, c.y, c.w, c.h}

	if font != nil {
		c._font = font
	} else {
		img := new_image_from_memory(#load("res/default_font_16x16.png"))
		c._font = new_font_from_image("default_font", img)
	}

	c._new_cells = Cells {
		make([]Index, w*h, c._allocator),
		make([]Color, w*h, c._allocator),
		make([]Color, w*h, c._allocator),
	}

	c._cells = Cells {
		make([]Index, w*h, c._allocator),
		make([]Color, w*h, c._allocator),
		make([]Color, w*h, c._allocator),
	}

	// c._rendering = Texture_Rendering{}  // slow af
	// c._rendering = Batch_Rendering{}    // slow af
	c._rendering = Shader_Rendering{}      // fast af

	for i in 0 ..< w*h {
		c._new_cells.glyphs[i] = DEF_GLYPH
		c._new_cells.fgs[i]    = DEF_FG
		c._new_cells.bgs[i]    = DEF_BG

		c._cells.glyphs[i] = 231
		c._cells.fgs[i]    = {231, 231, 231, 231}
		c._cells.bgs[i]    = {231, 231, 231, 231}
	}

	if _cw, ok := cw_ovr.?; ok do c._cw = _cw
	if _ch, ok := ch_ovr.?; ok do c._ch = _ch

	c._bg_tex    = k2.create_texture(c.w, c.h, .RGBA_8_Norm)
	c._bg_pixels = make([]u8, c.w*c.h*CHANNELS, c._allocator)

	_reset_console(c, false)
	return c
}


@private _free_console :: proc(c: ^Console) {
	free_all(c._allocator)

	virtual.arena_destroy(&c._arena)
	virtual.arena_destroy(&c._rend_arena)

	k2.destroy_texture(c._bg_tex)
	k2.destroy_render_texture(c._main_rtex)

	switch &rend in c._rendering {
		case Texture_Rendering: _destroy_rtex_rendering(c, &rend)
		case Batch_Rendering:   _destroy_batch_rendering(c, &rend)
		case Shader_Rendering:  _destroy_shader_rendering(c, &rend)
	}
	free(c)
}

@private _reset_console :: proc(c: ^Console, is_reset: bool) {

	// make sure these cells are different from the others, so the console
	//  updates everything
	for i in 0 ..< c.w*c.h {
		c._cells.glyphs[i] = 231
		c._cells.fgs[i] = {231, 231, 231, 231}
		c._cells.bgs[i] = {231, 231, 231, 231}
	}

	cw, ch := get_cell_size(c)
	k2.destroy_render_texture(c._main_rtex)
	c._main_rtex = k2.create_render_texture(c.w*cw, c.h*ch)



	switch &rend in c._rendering {
		case Texture_Rendering:
			_destroy_rtex_rendering(c, &c._rendering.(Texture_Rendering))
			_init_rtex_rendering(c,   &c._rendering.(Texture_Rendering), is_reset)
		case Batch_Rendering:
			_destroy_batch_rendering(c, &c._rendering.(Batch_Rendering))
			_init_batch_rendering(c,  &c._rendering.(Batch_Rendering), is_reset)
		case Shader_Rendering:
			_destroy_shader_rendering(c, &c._rendering.(Shader_Rendering))
			_init_shader_rendering(c, &c._rendering.(Shader_Rendering), is_reset)
	}
}

// Updates the internal contents of the console to be ready for rendering.
// There shouldn't be a need to manually call this procedure. It's called
// automatically in `render_console`.
// NOTE: changes made to the console's cells after this call, won't be rendered
// to the screen on the next call to `render_console`. This should only be
// called when no more changes are required before rendering.
_update :: proc(c: ^Console) {
	// t1 := time.tick_now()
	// don't update twice in the same frame
	if c._is_updated do return
	c._is_updated = true

	switch &rend in c._rendering {
		case Texture_Rendering:  _update_rtex_rendering(c, &rend)
		case Batch_Rendering:    _update_batch_rendering(c, &rend)
		case Shader_Rendering:   _update_shader_rendering(c, &rend)
	}

	// fmt.printfln("update in %d", time.tick_since(t1))
}

// Renders a console to the screen.
render :: proc(c: ^Console) {
	if !c._is_updated do _update(c)

	cw, ch := get_cell_size(c)
	rtr := k2.get_texture_rect(c._main_rtex.texture)

	k2.set_render_texture(c._main_rtex)
	{
		k2.clear({16, 0, 0, 1})

		switch &rend in c._rendering {
			case Texture_Rendering: _render_rtex_rendering(c, &rend)
			case Batch_Rendering:   _render_batch_rendering(c, &rend)
			case Shader_Rendering:  _render_shader_rendering(c, &rend)
		}
	}
	k2.set_render_texture(nil)

	dst_rect := Rectf{f32(c.x*cw), f32(c.y*ch), f32(c.w*cw), f32(c.h*ch)}
	// dst_rect := Rectf{0, 0, f32(c.w*cw), f32(c.h*ch)}
	k2.draw_texture_fit(c._main_rtex.texture, rtr, dst_rect, {}, 0, c.tint)

	c._is_updated = false // reset
}



/*******************************************************************************

		Internal

*******************************************************************************/
@private _set_glyph :: #force_inline proc(c: ^Console, idx: int, glyph: Maybe(Index)=nil) {
	if g, ok := glyph.?; ok do c._new_cells.glyphs[idx] = g
}

@private _set_fg :: #force_inline proc(c: ^Console, idx: int, fg: Maybe(Color)) {
	if f, ok := fg.?; ok do c._new_cells.fgs[idx] = f
}

@private _set_bg :: #force_inline proc(c: ^Console, idx: int, bg: Maybe(Color)) {
	if f, ok := bg.?; ok do c._new_cells.bgs[idx] = f
}

// Returns the console's width and height as separate values.
get_size :: proc(c: ^Console) -> (int, int) {
	return c.w, c.h
}

// Returns the console's width and height as a Vec2.
get_sizev :: proc(c: ^Console) -> Vec2 {
	return Vec2{c.w, c.h}
}

// Returns the font currently being used by the console.
get_font :: proc(c: ^Console) -> ^Font {
	return c._font
}

// Sets a new font to the console. This may change the window size if the
// console is the main console and the cell size changes.
set_font :: proc(c: ^Console, new_font: ^Font) {
	if new_font == c._font do return
	old_font := c._font
	c._font = new_font

	_reset_console(c, true)

	if c == internal.main_console \
	&& c._cw == 0 && (old_font.tw != new_font.tw || old_font.th != new_font.th)
	{
		_resize_window()
	}
}


is_position_in_bounds :: proc(c: ^Console, #any_int x, y: int) -> bool {
	ca := c._clip_area
	return x >= ca.x && x < ca.x+ca.w \
	    && y >= ca.y && y < ca.y+ca.h
}

is_rect_in_bounds :: proc(c: ^Console, #any_int x1, y1, x2, y2: int) -> bool {
	ca := c._clip_area
	return x2 >= ca.x && x1 < ca.x+ca.w  \
	    && y2 >= ca.y && y1 < ca.y+ca.h
}

//	Returns the rectangle of the console's clipping area (the are within which things can be drawn onto the console).
get_clipping_area :: proc(c: ^Console) -> Rect {
	return c._clip_area
}

// Set the rectangle of the console's clipping area (the are within which things can be drawn onto the console).
set_clipping_area :: proc(c: ^Console, r: Maybe(Rect) = nil) {
	if ca, ok := r.?; ok {
		c._clip_area = ca
	} else {
		c._clip_area = {0, 0, c.w, c.h}
	}
}


get_clipping_bounds :: proc(c: ^Console, x, y, w, h: int) -> (int, int, int, int) {
	left   := max(x,   c._clip_area.x)
	top    := max(y,   c._clip_area.y)
	right  := min(x+w, c._clip_area.x + c._clip_area.w)
	bottom := min(y+h, c._clip_area.y + c._clip_area.h)
	return left, top, right, bottom
}

// Returns the console's cell_size as two separate values. (This is not the same as the font's tile size (`font.tw`, `font.th`) if it was overridden.)
get_cell_size :: proc(c: ^Console) -> (int, int) {
	cw := c._cw > 0 ? c._cw : c._font.tw
	ch := c._ch > 0 ? c._ch : c._font.th
	return cw, ch
}

// Returns the console's cell_size as a Vec2. (This is not the same as the font's tile size (`font.tw`, `font.th`) if it was overridden.)
get_cell_sizev :: proc(c: ^Console) -> Vec2 {
	cw, ch := get_cell_size(c)
	return Vec2{cw, ch}
}

// Returns the position of the mouse, in cell coordinates, relative to the console.
get_mouse_position :: proc(c: ^Console) -> Vec2 {
	cw, ch := get_cell_size(c)
	mpos := get_screen_mouse_position()
	return (mpos - {c.x * cw, c.y * ch}) / {cw, ch}
}


_draw_points :: proc(c: ^Console, points: [dynamic]Vec2, index: Maybe(Index)=nil,
                           fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	for p in points {
		x, y, in_view := _transform_position_to_camera(p.x, p.y)
		if !in_view || !is_position_in_bounds(c, x, y) do continue
		idx := x + y*c.w
		_set_glyph(c, idx, index)
		_set_fg(c, idx, fg)
		_set_bg(c, idx, bg)
	}
}



/*******************************************************************************

		Cell API

*******************************************************************************/
// Clear the console to the default cell components
clear_cells :: proc(c: ^Console, bg: Maybe(Color) = nil) {
	bg, ok := bg.?
	if !ok do bg = DEF_BG

	for i in 0 ..< int(c.w*c.h) {
		_set_glyph(c, i, DEF_GLYPH)
		_set_fg(c, i, DEF_FG)
		_set_bg(c, i, bg)
	}
}


// Returns the cell at 'x' and 'y' position
get_cell :: proc(c: ^Console, #any_int x, y: int) -> (Cell, bool) #optional_ok {
	if !is_position_in_bounds(c, x, y) do return {DEF_GLYPH, DEF_FG, DEF_BG}, false
	idx := x+y*c.w
	cell := Cell {
		index_to_char(c._font, c._new_cells.glyphs[idx]),
		c._new_cells.fgs[idx],
		c._new_cells.bgs[idx]
	}
	return cell, true
}

// Returns the glyph of the cell at 'x' and 'y' position as a rune
get_glyph_rune :: proc(c: ^Console, #any_int x, y: int) -> (Rune, bool) #optional_ok {
	if !is_position_in_bounds(c, x, y) do return 0, false
	return index_to_char(c, c._new_cells.glyphs[x+y*c.w]), true
}

// Returns the glyph of the cell at 'x' and 'y' position as an index to the bitmap font
get_glyph_index :: proc(c: ^Console, #any_int x, y: int) -> (Index, bool) #optional_ok {
	if !is_position_in_bounds(c, x, y) do return 0, false
	return c._new_cells.glyphs[x+y*c.w], true
}

// Returns the foreground color of the cell at 'x' and 'y' position
get_fg :: proc(c: ^Console, #any_int x, y: int) -> (Color, bool) #optional_ok {
	if !is_position_in_bounds(c, x, y) do return {}, false
	return c._new_cells.fgs[x+y*c.w], true
}

// Returns the background color of the cell at 'x' and 'y' position
get_bg :: proc(c: ^Console, #any_int x, y: int) -> (Color, bool) #optional_ok {
	if !is_position_in_bounds(c, x, y) do return {}, false
	return c._new_cells.bgs[x+y*c.w], true
}



// Draw a cell at `x, y` position with the specified components, or a cell object.
draw_cell :: proc {
	draw_cell_rune,
	draw_cell_index,
	draw_cell_cell,
}

// Draw a cell at `x, y` position with the specified components,
// where `glyph` is a rune.
draw_cell_rune :: proc(c: ^Console, #any_int x, y: int, glyph: Rune,
                          fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	draw_cell_index(c, x, y, console_char_to_index(c, glyph), fg, bg)
}

// Draw the cell `cell` at `x, y` position.
draw_cell_cell :: proc(c: ^Console, #any_int x, y: int, cell: Cell) {
	draw_cell_index(c, x, y, console_char_to_index(c, cell.glyph), cell.fg, cell.bg)
}

// Draw a cell at `x, y` position with the specified components,
// where `glyph` is an index.
draw_cell_index :: proc(c: ^Console, #any_int x, y: int, glyph: Maybe(Index)=nil,
                           fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	x, y, in_view := _transform_position_to_camera(x, y)
	if !in_view || !is_position_in_bounds(c, x, y) do return

	idx := x+y*c.w
	_set_glyph(c, idx, glyph)
	_set_fg(c, idx, fg)
	_set_bg(c, idx, bg)
}


// Draw a `glyph` at `x, y` position.
draw_glyph :: proc {
	draw_glyph_index,
	draw_glyph_rune,
}

// Draw a `glyph` from an index at `x, y` position.
draw_glyph_index :: proc(c: ^Console, #any_int x, y: int, glyph: Index) {
	x, y, in_view := _transform_position_to_camera(x, y)
	if !in_view || !is_position_in_bounds(c, x, y) do return
	idx := x+y*c.w
	_set_glyph(c, idx, glyph)
}

// Draw a `glyph` from a rune at `x, y` position.
draw_glyph_rune :: proc(c: ^Console, #any_int x, y: int, glyph: Rune){
	x, y, in_view := _transform_position_to_camera(x, y)
	if !in_view || !is_position_in_bounds(c, x, y) do return
	idx := x+y*c.w
	_set_glyph(c, idx, console_char_to_index(c, glyph))
}

// Draw the `fg` foregound color at `x, y` position.
draw_fg :: proc(c: ^Console, #any_int x, y: int, fg: Color) {
	x, y, in_view := _transform_position_to_camera(x, y)
	if !in_view || !is_position_in_bounds(c, x, y) do return
	idx := x+y*c.w
	_set_fg(c, idx, fg)
}

// Draw the `bg` backgound color at `x, y` position.
draw_bg :: proc(c: ^Console, #any_int x, y: int, bg: Color) {
	x, y, in_view := _transform_position_to_camera(x, y)
	if !in_view || !is_position_in_bounds(c, x, y) do return
	idx := x+y*c.w
	_set_bg(c, idx, bg)
}



_transform_position_to_camera :: proc(x, y: int) -> (int, int, bool) {
	if internal.curr_camera == nil do return x, y, true
	x := camera_to_screen_x(internal.curr_camera, x)
	y := camera_to_screen_y(internal.curr_camera, y)
	in_view := camera_is_in_viewport(internal.curr_camera, x, y)
	return x, y, in_view
}


// Draws `text` to the console, starting at `x, y` position.
// No multi-line or formatting support.
draw_text :: proc(c: ^Console, #any_int x, y: int, text: string,
                      fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	x, y := x, y

	min_x := max(0, c._clip_area.x)
	min_y := max(0, c._clip_area.y)
	max_x := min(c.w, c._clip_area.w)
	max_y := min(c.h, c._clip_area.h)

	cam := internal.curr_camera
	if cam != nil {
		x = camera_to_screen_x(cam, x)
		y = camera_to_screen_y(cam, y)
		if !camera_is_in_viewport_y(cam, y) do return
	}

	if y < min_x || y >= max_y do return

	length := strings.rune_count(text)
	if x + length < min_x || x >= max_x do return

	runes := utf8.string_to_runes(text, context.temp_allocator)

	for i in 0 ..< len(runes) {
		xi := x + i
		if cam != nil && !camera_is_in_viewport_x(cam, xi) do continue
		if xi < min_x do continue // probably redundant
		if xi >= max_x do break
		idx := xi+y*c.w

		// TODO: layout shouldn't be hardcoded
		// glyph := _internal.font_layouts["cp437"].chars[ runes[i] ]
		glyph := console_char_to_index(c, Rune(runes[i]))

		_set_glyph(c, idx, glyph)
		_set_fg(c, idx, fg)
		_set_bg(c, idx, bg)
	}
}



// Draw a line from `x1, y1` to `x2, y2`, using the specified cell
// components, or a cell object.
draw_line :: proc {
	draw_line_rune,
	draw_line_index,
	draw_line_cell,
}

// Draw a line from `x1, y1` to `x2, y2`, using the specified cell components,
// where `glyph` is a rune.
draw_line_rune :: proc(c: ^Console, #any_int x1, y1, x2, y2: int,
            glyph: Rune, fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	draw_line_index(c, x1, y1, x2, y2, console_char_to_index(c, glyph), fg, bg)
}

// Draw a line from `x1, y1` to `x2, y2`, using the specified cell components,
// where `glyph` is an index.
draw_line_index :: proc(c: ^Console, #any_int x1, y1, x2, y2: int,
            glyph: Maybe(Index)=nil, fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	_draw_points(c, line_points(x1, y1, x2, y2), glyph, fg, bg)
}

// Draw a line from `x1, y1` to `x2, y2`, using the specified `cell`.
draw_line_cell :: proc(c: ^Console, #any_int x1, y1, x2, y2: int,
            cell: Cell) {
	draw_line_index(c, x1, y1, x2, y2, console_char_to_index(c, cell.glyph), cell.fg, cell.bg)
}



// Draw a rectangle `x, y, w, h`, using the specified cell components.
draw_rect :: proc {
	draw_rect_rune,
	draw_rect_index,
	draw_rect_cell,
}

// Draw a rectangle `x, y, w, h`, using the specified cell components, // where glyph is a rune.
draw_rect_rune :: proc(c: ^Console, filled: bool, #any_int x, y, w, h: int,
            glyph: Rune, fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	draw_rect_index(c, filled, x, y, w, h, console_char_to_index(c, glyph), fg, bg)
}

// Draw a rectangle `x, y, w, h`, using the specified cell components, // where glyph is an index.
draw_rect_index :: proc(c: ^Console, filled: bool, #any_int x, y, w, h: int,
            glyph: Maybe(Index)=nil, fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	if !is_rect_in_bounds(c, x, y, x+w-1, y+h-1) do return
	switch filled {
		case false: _draw_points(c, rect_points(x, y, w, h), glyph, fg, bg)
		case true:  _draw_points(c, rect_filled_points(x, y, w, h), glyph, fg, bg)
	}
}

// Draw a rectangle `x, y, w, h`, using the specified `cell`.
draw_rect_cell :: proc(c: ^Console, filled: bool, #any_int x, y, w, h: int,
            cell: Cell) {
	draw_rect_index(c, filled, x, y, w, h, console_char_to_index(c, cell.glyph), cell.fg, cell.bg)
}



// Draw a circle at `x, y` with radius `r`, using the specified cell components.
draw_circle :: proc {
	draw_circle_rune,
	draw_circle_index,
	draw_circle_cell,
}

// Draw a circle at `x, y` with radius `r`, using the specified cell components,
// where glyph is a rune.
draw_circle_rune :: proc(c: ^Console, filled: bool, #any_int x, y, r: int,
            glyph: Rune, fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	draw_circle_index(c, filled, x, y, r, console_char_to_index(c, glyph), fg, bg)
}

// Draw a circle at `x, y` with radius `r`, using the specified `cell`.
draw_circle_cell :: proc(c: ^Console, filled: bool, #any_int x, y,r: int,
            cell: Cell) {
	draw_circle_index(c, filled, x, y, r, console_char_to_index(c, cell.glyph), cell.fg, cell.bg)
}

// Draw a circle at `x, y` with radius `r`, using the specified cell components,
// where glyph is an index.
draw_circle_index :: proc(c: ^Console, filled: bool, #any_int x, y, r: int,
            glyph: Maybe(Index)=nil, fg: Maybe(Color)=nil, bg: Maybe(Color)=nil) {
	if !is_rect_in_bounds(c, x-r, y-r, x+r-1, y+r-1) do return
	switch filled {
		case false: _draw_points(c, circle_points(x, y, r), glyph, fg, bg)
		case true:  _draw_points(c, circle_filled_points(x, y, r), glyph, fg, bg)
	}
}


// TODO: this should be part of the Image API
@private _image_get_pixel :: proc(img: ^Image, x, y: int) -> (Color, bool) #optional_ok {
	if x < 0 || x >= img.w || y < 0 || y >= img.h {
		return {}, false
	}

	idx := (x+y*img.w)*CHANNELS
	c := Color {
		img.pixels[idx+0],
		img.pixels[idx+1],
		img.pixels[idx+2],
		img.pixels[idx+3],
	}
	return c, true
}


// draw `image` to the console, using a glyph and a foreground color.
draw_image :: proc{
	draw_image_fg_index,
	draw_image_fg_rune,
	draw_image_bg,
}

// draw `image` to the console, using a glyph and a foreground color,
// where glyph is a rune.
draw_image_fg_rune :: proc(c: ^Console, #any_int x, y: int, glyph: Rune,
                        image: ^Image, key_color: Maybe(Color) = nil
                    ) {
	draw_image_fg_index(c, x, y, console_char_to_index(c, glyph), image, key_color)
}

// draw `image` to the console, using a glyph and a foreground color,
// where glyph is an index.
draw_image_fg_index :: proc(c: ^Console, #any_int x, y: int,
                        glyph: Maybe(Index)=nil, image: ^Image,
                        key_color: Maybe(Color) = nil
                    ) {
	cam := internal.curr_camera
	x, y, in_view := _transform_position_to_camera(x, y)
	w, h := image.w, image.h
	if !is_rect_in_bounds(c, x, y, x+w-1, y+h-1) do return

	l, t, r, b := get_clipping_bounds(c, x, y, w, h)

	for j in 0 ..< h {
		for i in 0 ..< w {
			cx := x+i
			cy := y+j
			if cam != nil && !camera_is_in_viewport(cam, cx, cy) do continue
			if cx < l || cy < t || cx >= r || cy >= b do continue

			pix, ok := _image_get_pixel(image, i, j)
			if !ok do continue

			if key_color == nil || pix != key_color {
				idx := cx+cy*c.w
				_set_glyph(c, idx, glyph)
				_set_fg(c, idx, pix)
			}
		}
	}
}

// draw `image` to the console, using only only a background color.
draw_image_bg :: proc(c: ^Console, #any_int x, y: int, image: ^Image, key_color: Maybe(Color) = nil) {
	cam := internal.curr_camera
	x, y, in_view := _transform_position_to_camera(x, y)
	w, h := image.w, image.h
	if !is_rect_in_bounds(c, x, y, x+w-1, y+h-1) do return

	l, t, r, b := get_clipping_bounds(c, x, y, w, h)

	for j in 0 ..< h {
		for i in 0 ..< w {
			cx := x+i
			cy := y+j
			if cam != nil && !camera_is_in_viewport(cam, cx, cy) do continue
			if cx < l || cy < t || cx >= r || cy >= b do continue

			pix, ok := _image_get_pixel(image, i, j)
			if !ok do continue

			if key_color == nil || pix != key_color {
				_set_bg(c, cx+cy*c.w, pix)
			}
		}
	}
}
