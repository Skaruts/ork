/*

	Copyright (c) 2026 Skaruts

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

*/
/*******************************************************************************

		Odin REXPaint Utils   (version 26.5)


	Notes:
		REXPaint counts layers from 1 to 9, so all procs that take
		a layer index reflect this.


	Quick Reference:
		import rex "rexpaint_odin"

		img := rex.load_image("path/to/file")
		defer rex.unload_image(img)

		cell := rex.get_cell(img, 1, 5, 5)

		rex.set_fg(img, 1, 10, 10, {255, 128, 0, 255})

*******************************************************************************/
package rexpaint_odin

import "core:slice"
import "core:fmt"
import "core:bytes"
import "core:compress/gzip"



/*******************************************************************************
		A simple internal file helper (ignore it)
*******************************************************************************/
@(private="file")
_REX_File :: struct {
	data: bytes.Buffer,
	ofs: int,
}

@(private="file")
_file_move :: proc(rf: ^_REX_File, num_bytes: int) {
	rf.ofs += num_bytes
}

@(private="file")
_file_get_8 :: proc(rf: ^_REX_File) -> u8 {
	defer rf.ofs += 1
	return slice.to_type(rf.data.buf[rf.ofs: rf.ofs+1], u8)
}

@(private="file")
_file_get_32 :: proc(rf: ^_REX_File) -> int {
	defer rf.ofs += 4
	return int(slice.to_type(rf.data.buf[rf.ofs: rf.ofs+4], i32))
}

@(private="file")
_file_load :: proc(rf: ^_REX_File, file_path: string) {
	gzip.load_from_file(file_path, &rf.data)
}

@(private="file")
_file_unload :: proc(rf: ^_REX_File) {
	delete(rf.data.buf)
}



/*******************************************************************************

        REX Utils

*******************************************************************************/
@(private="file") __VERSION :: 0
@(private="file") _ERR_BOUNDS :: "index out of bounds: %d, %d, %d (layer, x, y)"


// Color is 4 bytes to make it compatible with most usages
// (in REXPaint they are only 3 bytes)
Color :: [4]u8


PINK   :: Color{ 255,   0, 255, 255 }
TRANSP :: Color{   0,   0,   0,   0 }
BLACK  :: Color{   0,   0,   0, 255 }


Transparency_Mode :: enum {
	REXPaint,
	Custom,
}


Cell :: struct {
	glyph : int,
	fg    : Color,
	bg    : Color,
}


@(private="file")
_REX_EMPTY_CELL :: Cell {32, BLACK, PINK}


Layer :: struct {
	glyphs      : []int,
	fgs         : []Color,
	bgs         : []Color,
}


Image :: struct {
	w, h         : int,
	version      : int,
	_empty_cell  : Cell,
	_transp_mode : Transparency_Mode,
	_layers      : [dynamic]Layer,
}


// Creates a new, empty image
new_image :: proc(#any_int w, h, num_layers: int, version := __VERSION) -> ^Image {
	img := new(Image)
	img.version      = version
	img.w            = w
	img.h            = h
	img._transp_mode = Transparency_Mode.REXPaint
	img._empty_cell  = _REX_EMPTY_CELL

	_init_all_layers(img, num_layers)
	clear(img)

	return img
}

// Loads a REXPaint `.xp` file from `file_path`.
load_image :: proc(file_path: string) -> ^Image {
	rf := _REX_File{}
	_file_load(&rf, file_path)
	defer _file_unload(&rf)

	version    := _file_get_32(&rf)
	num_layers := _file_get_32(&rf)
	w          := _file_get_32(&rf)
	h          := _file_get_32(&rf)
	_file_move(&rf, -8) // compensate for having already read the w, h of the first layer

	img := new_image(w, h, num_layers, version)

	for l in 0 ..< num_layers {
		// ignore width and height at the start of each layer
		_file_move(&rf, 8)
		layer := img._layers[l]

		for i in 0 ..< w { // rex paint uses column major order
			for j in 0 ..< h {
				idx := i+j*w
				layer.glyphs[idx] = _file_get_32(&rf)
				layer.fgs[idx]    = Color{ _file_get_8(&rf), _file_get_8(&rf), _file_get_8(&rf), 255 }
				layer.bgs[idx]    = Color{ _file_get_8(&rf), _file_get_8(&rf), _file_get_8(&rf), 255 }
			}
		}
	}

	return img
}

// Deletes an image and frees its memory.
unload_image :: proc(img: ^Image) {
	for i in 0 ..< len(img._layers) {
		_destroy_layer(img, i)
	}
	delete(img._layers)
	free(img)
}


@(private="file")
_destroy_layer :: proc(img: ^Image, idx: int) {
	delete(img._layers[idx].glyphs)
	delete(img._layers[idx].fgs)
	delete(img._layers[idx].bgs)
}


@(private="file")
_init_all_layers :: proc(img: ^Image, num_layers: int) {
	for i in 0 ..< num_layers {
		append(&img._layers, _init_layer(img))
	}
}


@(private="file")
_init_layer :: proc(img: ^Image) -> Layer {
	layer := Layer{}
	layer.glyphs = make([]int,   img.w*img.h)
	layer.fgs    = make([]Color, img.w*img.h)
	layer.bgs    = make([]Color, img.w*img.h)
	return layer
}

// Checks if two images are the same
is_equal :: proc(a, b: Image) -> bool {
	if a.w != b.w || a.h != b.h || len(a._layers) != len(b._layers) do return false
	for l in 0 ..< len(a._layers) {
		for i in 0 ..< a.w*a.h {
			if a._layers[l].glyphs[i] != b._layers[l].glyphs[i] \
			|| a._layers[l].fgs[i]    != b._layers[l].fgs[i]    \
			|| a._layers[l].bgs[i]    != b._layers[l].bgs[i]
			{
				return false
			}
		}
	}
	return true
}

// Clears the given image.
clear :: proc(img: ^Image) {
	for i in 1 ..= len(img._layers) {
		clear_layer(img, i)
	}
}


// fill layer at 'l' with empty cells
clear_layer :: proc(img: ^Image, l: int) {
	if l < 1 || l > len(img._layers) do return // TODO: error?
	layer := &img._layers[l-1]
	for i in 0 ..< img.w*img.h {
		layer.glyphs[i] = img._empty_cell.glyph
		layer.fgs[i]    = img._empty_cell.fg
		layer.bgs[i]    = img._empty_cell.bg
	}
}

// Checks if the given position and layer are within bounds of the iamge.
is_in_bounds :: proc(img: ^Image, l, x, y: int) -> bool {
	return l >  0 && l <= len(img._layers)    \
	    && x >= 0 && x < img.w               \
	    && y >= 0 && y < img.h
}


// Set the components of the cell at coordinates `x`, `y`, in layer `l`.
// Components passed as nil will be unchanged.
set_cell :: proc(img: ^Image, #any_int l, x, y: int, glyph: Maybe(int) = nil,
	             fg: Maybe(Color) = nil, bg: Maybe(Color) = nil) {

	if !is_in_bounds(img, l, x, y) do return

	idx := x+y*img.w
	layer := &img._layers[l-1]

	if g, ok := glyph.?; ok {
		layer.glyphs[idx] = g
	}

	if f, ok := fg.?; ok {
		layer.fgs[idx] = f
	}

	if b, ok := bg.?; ok {
		layer.bgs[idx] = b
	}
}


// set the `glyph` component of the cell at coordinates `x`, `y`, in layer `l`.
set_glyph :: proc(img: ^Image, #any_int l, x, y, glyph: int) {
	if !is_in_bounds(img, l, x, y) do return
	img._layers[l-1].glyphs[x+y*img.w] = glyph
}

// set the `fg` component of the cell at coordinates `x`, `y`, in layer `l`.
set_fg :: proc(img: ^Image, #any_int l, x, y:int, fg: Color) {
	if !is_in_bounds(img, l, x, y) do return
	img._layers[l-1].fgs[x+y*img.w] = fg
}

// set the `bg` component of the cell at coordinates `x`, `y`, in layer `l`.
set_bg :: proc(img: ^Image, #any_int l, x, y:int, bg: Color) {
	if !is_in_bounds(img, l, x, y) do return
	img._layers[l-1].bgs[x+y*img.w] = bg
}


// Get the `Cell` at coordinates `x` and `y` and in layer 'l'.
get_cell :: proc(img: ^Image, #any_int l, x, y: int) -> Cell {
	if !is_in_bounds(img, l, x, y) do fmt.panicf(_ERR_BOUNDS, l, x, y)
	i := x+y*img.w
	return {
		img._layers[l-1].glyphs[i],
		img._layers[l-1].fgs[i],
		img._layers[l-1].bgs[i],
	}
}


// Get the `glyph` component of the cell at coordinates `x` and `y` and in layer `layer`.
get_glyph :: proc(img: ^Image, #any_int l, x, y: int) -> int {
	if !is_in_bounds(img, l, x, y) do fmt.panicf(_ERR_BOUNDS, l, x, y)
	return img._layers[l-1].glyphs[x+y*img.w]
}


// Get the `fg` component of the cell at coordinates `x` and `y` and in layer `l`.
get_fg :: proc(img: ^Image, #any_int l, x, y: int) -> Color {
	if !is_in_bounds(img, l, x, y) do fmt.panicf(_ERR_BOUNDS, l, x, y)
	return img._layers[l-1].fgs[x+y*img.w]
}


// Get the `bg` component of the cell at coordinates `x` and `y` and in layer `l`.
get_bg :: proc(img: ^Image, #any_int l, x, y: int) -> Color {
	if !is_in_bounds(img, l, x, y) do fmt.panicf(_ERR_BOUNDS, l, x, y)
	return img._layers[l-1].bgs[x+y*img.w]
}


@(private="file")
_is_cell_transp :: proc(img: ^Image, glyph: int, fg, bg: Color) -> bool {
	if img._transp_mode == Transparency_Mode.REXPaint {
		return bg == PINK
	}
	return bg == TRANSP && (fg == TRANSP || glyph == 0)
}


// Check if a cell is transparent at the given coordinates and layer.
// A Cell can be passed in instead.
is_transparent :: proc {
	is_transparent_cell,
	is_transparent_at,
}


is_transparent_cell :: proc(img: ^Image, cell: Cell) -> bool {
	return _is_cell_transp(img, cell.glyph, cell.fg, cell.bg)
}


is_transparent_at :: proc(img: ^Image, #any_int l, x, y: int) -> bool {
	idx := x+y*img.w

	glyph := img._layers[l-1].glyphs[idx]
	fg    := img._layers[l-1].fgs[idx]
	bg    := img._layers[l-1].bgs[idx]

	return _is_cell_transp(img, glyph, fg, bg)
}




// Merge layers down from `top` to `bottom`.
// Layers are counted from 1..9.
merge_layers :: proc(img: ^Image, top := 9, bottom := 1) {
	top, bottom := top, bottom
	if top < bottom do bottom, top = top, bottom

	top    = min(top-1, len(img._layers)-1)
	bottom = max(bottom-1, 0)

	if len(img._layers) == 1 || bottom == top do return

	bc, bf, bb := &img._layers[bottom].glyphs, &img._layers[bottom].fgs, &img._layers[bottom].bgs
	for l in bottom+1 ..< top {
		tc, tf, tb := &img._layers[l].glyphs, &img._layers[l].fgs, &img._layers[l].bgs
		for i in 0 ..< img.w*img.h {
			if !_is_cell_transp(img, tc[i], tf[i], tb[i]) {
				bc[i] = tc[i]
				bf[i] = tf[i]
				bb[i] = tb[i]
			}
		}
	}

	// remove merged _layers
	for top != bottom {
		_destroy_layer(img, top)
		ordered_remove(&img._layers, top)
		top -= 1
	}
}



// Set custom cell components to use for transparent cells.
// NOTE: this is a heavy operation, as it converts all the transparent cells
// in the entire image.
set_transparent_cell :: proc {
	set_transparent_cell_from_comps,
	set_transparent_cell_from_cell,
}

set_transparent_cell_from_comps :: proc(img: ^Image, glyph: int, fg, bg: Color) {
	set_transparent_cell_from_cell(img, {glyph, fg, bg})
}

set_transparent_cell_from_cell :: proc(img: ^Image, cell: Cell) {
	img._transp_mode = Transparency_Mode.Custom
	img._empty_cell = cell

	for l in 0 ..< len(img._layers) {
		cl, fl, bl := &img._layers[l].glyphs, &img._layers[l].fgs, &img._layers[l].bgs
		for i in 0 ..< img.w*img.h {
			if bl[i] == PINK {
				cl[i] = cell.glyph
				fl[i] = cell.fg
				bl[i] = cell.bg
			}
		}
	}
}


// Reset the transparent cells back to REXPaint's default (32, black, pink)
// NOTE: this is a heavy operation, as it converts all the transparent cells
// in the entire image.
reset_transparent_cell :: proc(img: ^Image) {
	if img._transp_mode == Transparency_Mode.REXPaint do return

	img._transp_mode = Transparency_Mode.REXPaint
	img._empty_cell = _REX_EMPTY_CELL

	for l in 0 ..< len(img._layers) {
		cl, fl, bl := &img._layers[l].glyphs, &img._layers[l].fgs, &img._layers[l].bgs
		for i in 0 ..< img.w*img.h {
			if bl[i] == PINK {
				cl[i] = _REX_EMPTY_CELL.glyph
				fl[i] = _REX_EMPTY_CELL.fg
				bl[i] = _REX_EMPTY_CELL.bg
			}
		}
	}
}


// Inserts a new layer at index `index`. Does nothing if image has maximum _layers.
insert_layer :: proc(img: ^Image, idx: int) {
	if len(img._layers) >= 9 do return  // TODO: report error?
	if idx < 1 || idx > len(img._layers) do return
	layer := _init_layer(img)
	inject_at(&img._layers, idx-1, layer)
}


// Removes layer at index 'index'. Does nothing if there's only one layer.
remove_layer :: proc(img: ^Image, idx: int) {
	if len(img._layers) == 0 do return
	if idx < 1 || idx > len(img._layers) do return

	_destroy_layer(img, idx-1)
	ordered_remove(&img._layers, idx-1)
}



