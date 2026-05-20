package ork


import "core:math"




// An FOV cell structure.
FovCell :: struct {
	transparent : bool,
	walkable    : bool,
	visible     : bool,
}

// This is only used internally to make square FOVs round.
// It has no other intended use and can be ignored entirely.
CircleMask :: []u8

// A map of FovCells, used in FOV algorithms.
Fovmap :: struct {
	w, h         : int,
	cells        : []FovCell,

	_circle_mask : CircleMask,
	_last_radius : int,
}

// An enumeration of the available FOV types.
FovType :: enum {
	Shadowcast,
	Restrictive,
	Diamond,
	// Permissive1,
	// Permissive2,
	// Permissive3,
	// Permissive4,
	// Permissive5,
	// Permissive6,
	// Permissive7,
	// Permissive8,
	// Permissive9,
}



// Returns a new `Fovmap` of `w, h` size.
new_fov :: proc(w, h: int) -> ^Fovmap {
	fovmap := _fov_create(w, h)
	append(&internal.fovmaps, fovmap)
	return fovmap
}

// Destroys the given `Fovmap` and frees its memory.
delete_fov :: proc(fovmap: ^Fovmap, loc := #caller_location) {
	if fovmap == nil do return
	idx, ok := _get_item_index(internal.fovmaps[:], fovmap)
	if ok do unordered_remove(&internal.fovmaps, idx)
	_fov_destroy(fovmap)
}

// Computes visibily within `radius` of position `pos`, using the chosen `FovType`.
// If `light_walls` is false, then walls will not be made visible by the algorithm.
fov_compute :: proc(fovmap: ^Fovmap, pos: Vec2, radius: int, type: FovType, light_walls := true, loc := #caller_location) {
	assert(radius > 0, "fov radius must be > 0", loc=loc)
 	x := int(pos.x)
 	y := int(pos.y)
 	fov_clear_radius(fovmap, x, y, radius)

	#partial switch type {
		case .Shadowcast:  _compute_shadowcast(fovmap, x, y, radius, light_walls)
		case .Restrictive: _compute_restrictive(fovmap, x, y, radius, light_walls)
		case .Diamond:     _compute_diamond_raycasting(fovmap, x, y, radius, light_walls)
		// case .Permissive1: _recompute_permissive5_perm2(fovmap, x, y, radius, light_walls)
		// case .Permissive2: _recompute_permissive5_perm3(fovmap, x, y, radius, light_walls)
		// case .Permissive3: _recompute_permissive5_perm4(fovmap, x, y, radius, light_walls)
		// case .Permissive4: _recompute_permissive5_perm5(fovmap, x, y, radius, light_walls)
		// case .Permissive5: _recompute_permissive5_perm6(fovmap, x, y, radius, light_walls)
		// case .Permissive6: _recompute_permissive5_perm7(fovmap, x, y, radius, light_walls)
		// case .Permissive7: _recompute_permissive5_perm8(fovmap, x, y, radius, light_walls)
		// case .Permissive8: _recompute_permissive5_perm9(fovmap, x, y, radius, light_walls)
		// case .Permissive9: _recompute_permissive5_permA(fovmap, x, y, radius, light_walls)
	}
}


@private _fov_create :: proc(w, h: int) -> ^Fovmap {
	assert(w > 0 && h > 0, "Fovmap width and height must be greater than zero")
	fovmap := new(Fovmap)
	fovmap.w = w
	fovmap.h = h
	fovmap.cells = make([]FovCell, w*h)
	return fovmap
}


@private _fov_destroy :: proc(fovmap: ^Fovmap) {
	delete(fovmap._circle_mask)
	delete(fovmap.cells)
	free(fovmap)
}


// Returns whether the position `x, y` is within bounds of `fovmap`.
fov_is_in_bounds :: proc(fovmap: ^Fovmap, x, y: int) -> bool {
	return x >= 0 && y >= 0 && x < fovmap.w && y < fovmap.h
}


// Sets the given properties of the FovCell at `x, y`.
fov_set_cell :: proc(fovmap: ^Fovmap, x, y:int, transparent:Maybe(bool)=nil,
                 walkable:Maybe(bool)=nil, visible:Maybe(bool)=nil
                ) {
	cell := &fovmap.cells[x+y*fovmap.w]

	if t, ok := transparent.?; ok do cell.transparent = t
	if w, ok := walkable.?;    ok do cell.walkable = w
	if v, ok := visible.?;     ok do cell.visible = v
}

// Clears the entire Fovmap.
fov_clear :: proc(fovmap: ^Fovmap) {
	for j in 0 ..< fovmap.h {
		for i in 0 ..< fovmap.w {
			fovmap.cells[i+j*fovmap.w].visible = false
		}
	}
}

// Clears an area of `fovmap` within `radius` of `x, y`.
// `radius` is actually used as a square range, instead of a circular one.
fov_clear_radius :: proc(fovmap: ^Fovmap, x, y, radius:int) {
	LEFT   := max( x-(radius+4),  0    )
	RIGHT  := min( x+(radius+4),  fovmap.w )
	TOP    := max( y-(radius+4),  0    )
	BOTTOM := min( y+(radius+4),  fovmap.h )

	for j in TOP ..< BOTTOM {
		for i in LEFT ..< RIGHT {
			fovmap.cells[i+j*fovmap.w].visible = false
		}
	}
}



// Sets the visibility of the FovCell at `x, y`.
fov_set_visible :: proc(fovmap: ^Fovmap, x, y: int, visible: bool, light_walls := true) {
	if !fov_is_in_bounds(fovmap, x, y) do return
	if !light_walls && !fovmap.cells[x+y*fovmap.w].transparent do return
	fovmap.cells[x+y*fovmap.w].visible = visible
}

// No-bounds-check version of `fov_set_visible`.
fov_set_visible_nc :: proc(fovmap: ^Fovmap, x, y: int, visible: bool, light_walls := true) {
	if !light_walls && !fovmap.cells[x+y*fovmap.w].transparent do return
	fovmap.cells[x+y*fovmap.w].visible = visible
}



// Returns whether the FovCell at `x, y` is visible.
fov_is_visible :: proc(fovmap: ^Fovmap, x, y: int) -> bool {
	return fov_is_in_bounds(fovmap, x, y) && fovmap.cells[x+y*fovmap.w].visible
}

// No-bounds-check version of `fov_is_visible`.
fov_is_visible_nc :: proc(fovmap: ^Fovmap, x, y: int) -> bool {
	return fovmap.cells[x+y*fovmap.w].visible
}

// Returns whether the FovCell at `x, y` is transparent.
fov_is_transparent :: proc(fovmap: ^Fovmap, x, y: int) -> bool {
	return fov_is_in_bounds(fovmap, x, y) && fovmap.cells[x+y*fovmap.w].transparent
}

// No-bounds-check version of `fov_is_transparent`.
fov_is_transparent_nc :: proc(fovmap: ^Fovmap, x, y: int) -> bool {
	return fovmap.cells[x+y*fovmap.w].transparent
}

// Returns whether the FovCell at `x, y` is walkable.
fov_is_walkable :: proc(fovmap: ^Fovmap, x, y: int) -> bool {
	return fov_is_in_bounds(fovmap, x, y) && fovmap.cells[x+y*fovmap.w].walkable
}

// No-bounds-check version of `fov_is_walkable`.
fov_is_walkable_nc :: proc(fovmap: ^Fovmap, x, y: int) -> bool {
	return fovmap.cells[x+y*fovmap.w].walkable
}





/*******************************************************************************

		Post Process

*******************************************************************************/

// Lights up walls, for FOVs that don't light walls during computation (e.g. Diamond)
@private _postprocess_light_walls :: proc(fovmap: ^Fovmap, x, y, radius: int) {
	size  := radius*2 + 1
	min_x := x-radius
	min_y := y-radius

	for j in 0 ..< size {
		for i in 0 ..< size {
			mx, my := min_x+i, min_y+j

			if !fov_is_in_bounds(fovmap, mx, my) \
			|| fov_is_transparent_nc(fovmap, mx, my) {
				continue
			}

			for i in 1 ..< 8 {
				nb_x := mx + DIRECTIONS[Direction(i)].x
				nb_y := my + DIRECTIONS[Direction(i)].y

				if !fov_is_in_bounds(fovmap, nb_x, nb_y) do continue

				// if a neighbor is floor and visible, this wall should be lit
				if fov_is_visible_nc(fovmap, nb_x, nb_y) \
				&& fov_is_walkable_nc(fovmap, nb_x, nb_y) {
					fov_set_visible_nc(fovmap, mx, my, true, true)
					break
				}
			}
		}
	}
}


// Make square fovs round.
@private _post_process_make_rounded :: proc(fovmap: ^Fovmap, x, y, radius: int, light_walls := true) {
	size := radius*2 + 1

	// if fov radius changed, create a new circle mask
	if radius != fovmap._last_radius {
		fovmap._last_radius = radius
		points := circle_filled_points(radius, radius, radius)

		delete(fovmap._circle_mask)
		fovmap._circle_mask = make(CircleMask, size*size)

		cells := &fovmap._circle_mask
		for p in points {
			cells[p.x+p.y*size] = 1
		}
	}

	// apply the fov circle mask
	for j in 0 ..< size {
		for i in 0 ..< size {
			px := x + i - radius
			py := y + j - radius

			if fovmap._circle_mask[i+j*size] == 0 \
			&& fov_is_in_bounds(fovmap, px, py) {
				fov_set_visible_nc(fovmap, px, py, false, light_walls)
			}
		}
	}
}



/******************************************************************************/
/*          Recursive Shadowcasting

	    Ported from: TODO: find out

    ***************************************************************************/
    @private
	_compute_shadowcast :: proc(fovmap: ^Fovmap, pos_x, pos_y, radius: int,
		                        light_walls := true) {
		mult := [][]int {
		   // xx, xy, yx, yy
		   {  1,  0,  0,  1 }, 	// N W
		   {  0,  1,  1,  0 },	// W N
		   {  0, -1,  1,  0 },	// E N
		   { -1,  0,  0,  1 },  // N E
		   { -1,  0,  0, -1 },  // S E
		   {  0, -1, -1,  0 },  // E S
		   {  0,  1, -1,  0 },  // W S
		   {  1,  0,  0, -1 },  // S W
		}

		fov_set_visible_nc(fovmap, pos_x, pos_y, true, light_walls)	// make starting point visible

		for oct in 0 ..< 8 {
			_cast_light(fovmap, pos_x, pos_y,
				1, 1.0, 0.0, radius,
				mult[oct][0], mult[oct][1],
				mult[oct][2], mult[oct][3],
				light_walls
			)
		}
	}

	@private
	_cast_light :: proc(fovmap: ^Fovmap, pos_x, pos_y, row: int,
		                start, ending: f32, radius: int,
		                xx, xy, yx, yy: int, light_walls := true) {
		if start < ending do return

		start := start

		diam := radius*radius

		for j in row ..= radius {  // TODO: double check this loop with the original
			dx := int(-j - 1)
			dy := int(-j)
			prev_blocked := false
			new_start: f32 = 0.0
			l_slope: f32
			r_slope: f32

			for dx <= 0 {
				dx += 1

				// Translate the dx, dy coordinates into map coordinates:
				x := pos_x + dx * xx + dy * xy
				y := pos_y + dx * yx + dy * yy

				// l_slope and r_slope store the slopes of the left and right
				// extremities of the square we're considering:
				l_slope = (f32(dx) - 0.5) / (f32(dy) + 0.5)
				r_slope = (f32(dx) + 0.5) / (f32(dy) - 0.5)

				if start < r_slope do continue
				if ending > l_slope do break

				in_bounds := fov_is_in_bounds(fovmap, x, y)

				// Our light beam is touching this square; light it
				if in_bounds && dx*dx + dy*dy < diam {
					fov_set_visible_nc(fovmap, x, y, true, light_walls)
				}

				if prev_blocked {
					// we're scanning a row of blocked squares
					if in_bounds && !fov_is_transparent_nc(fovmap, x, y) {
						new_start = r_slope
						continue
					} else {
						prev_blocked = false
						start = new_start
					}
				} else {
					if in_bounds && !fov_is_transparent_nc(fovmap, x, y) && j < radius {
						// This is a blocking square, start a child scan:
						prev_blocked = true
						_cast_light(fovmap, pos_x, pos_y, j+1, start, l_slope, radius, xx, xy, yx, yy, light_walls)
						new_start = r_slope
					}
				}
			}

			// Row is scanned; do next row unless last square was blocked
			if prev_blocked do break
		}
	}
/******************************************************************************/



/******************************************************************************/
/*          Mingo's Restrictive Precise Angle Shadowcasting

	    Original:
	        https://bitbucket.org/umbraprojekt/mrpas (some other fovs there too)

	    Ported from:
	        https://github.com/domasx2/mrpas-js/blob/master/mrpas.js

	***************************************************************************/
	@private
	_compute_restrictive :: proc(fovmap: ^Fovmap, x, y, radius: int, light_walls := true, rounded := true) {
		// make starting point visible
		fov_set_visible_nc(fovmap, x, y, true, light_walls)

		// compute the 4 quadrants of the fov
		_mrpas_js_compute_quadrant(fovmap, x, y, radius,  1,  1, light_walls)
		_mrpas_js_compute_quadrant(fovmap, x, y, radius,  1, -1, light_walls)
		_mrpas_js_compute_quadrant(fovmap, x, y, radius, -1,  1, light_walls)
		_mrpas_js_compute_quadrant(fovmap, x, y, radius, -1, -1, light_walls)

		if rounded {
			_post_process_make_rounded(fovmap, x, y, radius, light_walls)
		}
	}


	@private
	_mrpas_js_compute_quadrant :: proc(fovmap: ^Fovmap, pos_x, pos_y, radius, dx, dy: int, light_walls := true) {
		// NOTE (skatuts): using fixed arrays here is faster, and 100 seems to be
		// well above what this algorithm needs, but I'm not 100% sure of it.
		start_angle : [100]f32
		end_angle : [100]f32

		//  octant: vertical edge:
		//  - - - - - - - - - - - - - - - - - - - - - - -
		iteration              : int  = 1
		done                   : bool = false
		total_obstacles        : int  = 0
		obstacles_in_last_line : int  = 0
		min_angle              : f32  = 0.0

		x: int = 0
		y: int = pos_y + dy

		slopes_per_cell : f32
		half_slopes     : f32
		start_slope     : f32
		end_slope       : f32
		center_slope    : f32
		processed_cell  : int
		visible         : bool
		idx             : int
		minx, maxx      : int
		miny, maxy      : int

		if y < 0 || y >= fovmap.h do done = true

		for !done {
			slopes_per_cell = 1.0 / f32(iteration + 1)
			half_slopes = slopes_per_cell * 0.5
			processed_cell = int(math.floor(min_angle / slopes_per_cell))

			minx = max(         0, pos_x - iteration)
			maxx = min(fovmap.w-1, pos_x + iteration)
			done = true
			x = pos_x + (processed_cell * dx)

			for x >= minx && x <= maxx {
				visible = true

				start_slope = f32(processed_cell) * slopes_per_cell
				center_slope = start_slope + half_slopes
				end_slope = start_slope + slopes_per_cell

				if obstacles_in_last_line > 0 && !fov_is_visible_nc(fovmap, x, y) {
					idx = 0
					for visible && idx < obstacles_in_last_line {
						if fov_is_transparent_nc(fovmap, x, y) {
							if center_slope > start_angle[idx] && center_slope < end_angle[idx] {
								visible = false
							}
						} else if start_slope >= start_angle[idx] && end_slope <= end_angle[idx] {
							visible = false
						}

						xdx := x - dx
						ydy := y - dy

						if visible && ( !fov_is_visible_nc(fovmap, x, ydy) || !fov_is_transparent_nc(fovmap, x, ydy) ) \
						&& ( xdx >= 0 && xdx < fovmap.w	&& ( !fov_is_visible_nc(fovmap, xdx, ydy) || !fov_is_transparent_nc(fovmap, xdx, ydy)  ))
						{
							visible = false
						}
						idx += 1
					}
				}

				if visible {
					fov_set_visible_nc(fovmap, x, y, true, light_walls)
					done = false

					// if the cell is opaque, block the adjacent slopes
					if !fov_is_transparent_nc(fovmap, x, y) {
						if min_angle >= start_slope {
							min_angle = end_slope
						} else {
							start_angle[total_obstacles] = start_slope
							end_angle[total_obstacles] = end_slope
							// append(&start_angle, start_slope)
							// append(&end_angle, end_slope)
							total_obstacles += 1
						}
					}
				}
				processed_cell += 1
				x += dx
			}

			if iteration >= radius do done = true

			iteration += 1
			obstacles_in_last_line = total_obstacles

			y += dy
			if y < 0 || y >= fovmap.h do done = true
			if min_angle == 1.0 do done = true
		}


		// octant: horizontal edge
		//  - - - - - - - - - - - - - - - - - - - - - - -
		iteration              = 1
		done                   = false
		total_obstacles        = 0
		obstacles_in_last_line = 0
		min_angle              = 0.0

		x = pos_x + dx // the outer slope's coordinates (first processed line)
		y = 0

		slopes_per_cell = 0
		half_slopes     = 0
		start_slope     = 0
		end_slope       = 0
		center_slope    = 0
		processed_cell  = 0
		visible         = false
		idx             = 0
		minx, maxx      = 0, 0
		miny, maxy      = 0, 0

		if x < 0 || x >= fovmap.w do done = true

		for !done {
			slopes_per_cell = 1.0 / f32(iteration + 1)
			half_slopes = slopes_per_cell * 0.5
			processed_cell = int(math.floor(min_angle / slopes_per_cell))

			miny = max(       0, pos_y - iteration)
			maxy = min(fovmap.h-1, pos_y + iteration)
			done = true
			y = pos_y + (processed_cell * dy)

			for y >= miny && y <= maxy {
				visible = true

				start_slope = f32(processed_cell) * slopes_per_cell
				center_slope = start_slope + half_slopes
				end_slope = start_slope + slopes_per_cell

				if obstacles_in_last_line > 0 && !fov_is_visible_nc(fovmap, x, y) {
					idx = 0

					for visible && idx < obstacles_in_last_line {
						if fov_is_transparent_nc(fovmap, x, y) {
							if center_slope > start_angle[idx] && center_slope < end_angle[idx] {
								visible = false
							}
						} else if start_slope >= start_angle[idx] && end_slope <= end_angle[idx] {
							visible = false
						}

						xdx := x-dx
						ydy := y-dy

						if visible && ( !fov_is_visible_nc(fovmap, xdx, y) || !fov_is_transparent_nc(fovmap, xdx, y) )  \
						&& ( ydy >= 0 && ydy < fovmap.h && ( !fov_is_visible_nc(fovmap, xdx, ydy) || !fov_is_transparent_nc(fovmap, xdx, ydy) ) )
						{
							visible = false
						}
						idx += 1
					}
				}
				if visible {
					fov_set_visible_nc(fovmap, x, y, true, light_walls)
					done = false

					// if the cell is opaque, block the adjacent slopes
					if !fov_is_transparent_nc(fovmap, x, y) {
						if min_angle >= start_slope {
							min_angle = end_slope
						} else {
							start_angle[total_obstacles] = start_slope
							end_angle[total_obstacles] = end_slope
							total_obstacles = total_obstacles + 1
						}
					}
				}
				processed_cell += 1
				y += dy
			}
			if iteration >= radius do done = true

			iteration += 1
			obstacles_in_last_line = total_obstacles

			x += dx
			if x < 0 || x >= fovmap.w do done = true
			if min_angle == 1.0 do done = true
		}
	}
/******************************************************************************/



/******************************************************************************/
/*          Diamond
	***************************************************************************/
	/* BSD 3-Clause License

		Copyright © 2008-2021, Jice and the libtcod contributors.
		All rights reserved.

		Redistribution and use in source and binary forms, with or without
		modification, are permitted provided that the following conditions are met:

		1. Redistributions of source code must retain the above copyright notice,
			 this list of conditions and the following disclaimer.

		2. Redistributions in binary form must reproduce the above copyright notice,
			 this list of conditions and the following disclaimer in the documentation
			 and/or other materials provided with the distribution.

		3. Neither the name of the copyright holder nor the names of its
			 contributors may be used to endorse or promote products derived from
			 this software without specific prior written permission.

		THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
		AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
		IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
		ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
		LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
		CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
		SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
		INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
		CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
		ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
		POSSIBILITY OF SUCH DAMAGE.
	*/

	// A discrete diamond raycast tile.
	@private RaycastTile :: struct {
		x_relative,  y_relative  : int,          // Ray position relative to the POV.
		x_obscurity, y_obscurity : int,          // Obscurity vector.
		x_error,     y_error     : int,          // Bresenham error.
		x_input,     y_input     : ^RaycastTile, // Pointer to the x/y-adjacent source ray.
		perimeter_next           : ^RaycastTile, // The next queued raycast of the perimeter.
		touched                  : bool,         // Becomes true once this ray is added to the perimeter.
		ignore                   : bool,         // Marked as non visible.
	}


	// Return a rays squared distance from the origin POV.
	@private _ray_length_sq :: proc(ray: ^RaycastTile) -> int {
		return (ray.x_relative * ray.x_relative)  \
		     + (ray.y_relative * ray.y_relative)
	}


	// The diamond raycast state.
	@private DiamondFov :: struct {
		fovmap        : ^Fovmap,
		x              : int,          // Fov origin point, the POV.
		y              : int,
		raymap_grid    : []^RaycastTile, // Grid of temporary rays.
		perimeter_last : ^RaycastTile, // Pointer to the last tile on the perimeter.
	}


	// Return a pointer to the tile belonging relative to the POV.
	// Returns nil if the tile would be out-of-bounds.
	@private _get_ray :: proc(fov: ^DiamondFov, relative_x, relative_y: int) -> ^RaycastTile {
		x := fov.x + relative_x
		y := fov.y + relative_y
		if !fov_is_in_bounds(fov.fovmap, x, y) {
			return nil
		}
		ray := fov.raymap_grid[x + y * fov.fovmap.w]
		ray.x_relative = relative_x
		ray.y_relative = relative_y
		return ray
	}


	// Configure the relationships of `new_ray` and add it to the perimeter.
	// `input_ray` is the source tile for `new_ray`.
	@private _process_ray :: proc(fov: ^DiamondFov, new_ray: ^RaycastTile, input_ray: ^RaycastTile) {
		if new_ray == nil do return

		if new_ray.y_relative == input_ray.y_relative {
			new_ray.x_input = input_ray
		} else {
			new_ray.y_input = input_ray
		}
		if !new_ray.touched {
			// Add this new tile to the perimeter.
			fov.perimeter_last.perimeter_next = new_ray
			fov.perimeter_last = new_ray
			new_ray.touched = true
		}
	}


	// Return true if this tile is obstructed.
	@private _is_obscured :: proc(ray: ^RaycastTile) -> bool {
		return (ray.x_error > 0 && ray.x_error <= ray.x_obscurity)  \
		    || (ray.y_error > 0 && ray.y_error <= ray.y_obscurity)
	}


	@private _process_x_input :: proc(new_ray, x_input: ^RaycastTile) {
		if x_input.x_obscurity == 0 && x_input.y_obscurity == 0 {
			return
		}

		if x_input.x_error > 0 && new_ray.x_obscurity == 0 {
			new_ray.x_error     = x_input.x_error - x_input.y_obscurity
			new_ray.y_error     = x_input.y_error + x_input.y_obscurity
			new_ray.x_obscurity = x_input.x_obscurity
			new_ray.y_obscurity = x_input.y_obscurity
		}

		if x_input.y_error <= 0 && x_input.y_obscurity > 0 && x_input.x_error > 0 {
			new_ray.y_error     = x_input.y_error + x_input.y_obscurity
			new_ray.x_error     = x_input.x_error - x_input.y_obscurity
			new_ray.x_obscurity = x_input.x_obscurity
			new_ray.y_obscurity = x_input.y_obscurity
		}
	}


	@private _process_y_input :: proc(new_ray, y_input: ^RaycastTile) {
		if y_input.x_obscurity == 0 && y_input.y_obscurity == 0 {
			return
		}

		if y_input.y_error > 0 && new_ray.y_obscurity == 0 {
			new_ray.y_error     = y_input.y_error - y_input.x_obscurity
			new_ray.x_error     = y_input.x_error + y_input.x_obscurity
			new_ray.x_obscurity = y_input.x_obscurity
			new_ray.y_obscurity = y_input.y_obscurity
		}

		if y_input.x_error <= 0 && y_input.x_obscurity > 0 && y_input.y_error > 0 {
			new_ray.y_error     = y_input.y_error - y_input.x_obscurity
			new_ray.x_error     = y_input.x_error + y_input.x_obscurity
			new_ray.x_obscurity = y_input.x_obscurity
			new_ray.y_obscurity = y_input.y_obscurity
		}
	}


	// Combine this rays source tiles to tell how obscured `ray` is.
	@private _merge_input :: proc(fov: ^DiamondFov, ray: ^RaycastTile) {
		x := ray.x_relative + fov.x
		y := ray.y_relative + fov.y

		if ray.x_input != nil do _process_x_input(ray, ray.x_input)
		if ray.y_input != nil do _process_y_input(ray, ray.y_input)

		if ray.x_input != nil || ray.y_input != nil {
			if ray.x_input == nil {
				if _is_obscured(ray.y_input) {
					ray.ignore = true
				}
			} else if ray.y_input == nil {
				if _is_obscured(ray.x_input) {
					ray.ignore = true
				}
			} else if _is_obscured(ray.x_input) && _is_obscured(ray.y_input) {
				ray.ignore = true
			}
		}

		if !ray.ignore && !fov_is_transparent_nc(fov.fovmap, x, y) {
			ray.x_error     = abs(ray.x_relative)
			ray.y_error     = abs(ray.y_relative)
			ray.x_obscurity = ray.x_error
			ray.y_obscurity = ray.y_error
		}
	}


	// Expand the perimeter outwards from this tile.
	@private _expand_perimeter_from :: proc(fov: ^DiamondFov, ray: ^RaycastTile) {
		if ray.ignore do return  // This tile was excluded from the perimeter.

		if ray.x_relative >= 0 {
			_process_ray(fov, _get_ray(fov, ray.x_relative + 1, ray.y_relative), ray)
		}
		if ray.x_relative <= 0 {
			_process_ray(fov, _get_ray(fov, ray.x_relative - 1, ray.y_relative), ray)
		}
		if ray.y_relative >= 0 {
			_process_ray(fov, _get_ray(fov, ray.x_relative, ray.y_relative + 1), ray)
		}
		if ray.y_relative <= 0 {
			_process_ray(fov, _get_ray(fov, ray.x_relative, ray.y_relative - 1), ray)
		}
	}


	@private _compute_diamond_raycasting :: proc(fovmap: ^Fovmap, x, y, max_radius: int, light_walls := true) {
		radius_squared := max_radius * max_radius

		if !fov_is_in_bounds(fovmap, x, y) {
			return
		}

		fov_set_visible_nc(fovmap, x, y, true, light_walls)

		fov := DiamondFov {
			fovmap = fovmap,
			x = x,
			y = y,
			raymap_grid = make([]^RaycastTile, len(fovmap.cells))// calloc(sizeof(*fov.raymap_grid), fovmap.nbcells),
		}

		for i in 0 ..< len(fovmap.cells) {
			tile := new(RaycastTile)
			fov.raymap_grid[i] = tile
		}

		// Add the origin ray tile to start the process.
		current_ray := _get_ray(&fov, 0, 0)
		fov.perimeter_last = current_ray
		current_ray.touched = true

		_expand_perimeter_from(&fov, current_ray)

		// Iterative over the diamond perimeter.
		for current_ray != nil {
			defer current_ray = current_ray.perimeter_next

			if radius_squared <= 0 || _ray_length_sq(current_ray) <= radius_squared {
				_merge_input(&fov, current_ray)
			} else {
				current_ray.ignore = true    // Mark out-of-range tiles as ignored.
			}
			_expand_perimeter_from(&fov, current_ray)

			// Check if this tile is visible.
			// current_ray.touched is true.
			if current_ray.ignore do continue

			if current_ray.x_error > 0 \
			&& current_ray.x_error <= current_ray.x_obscurity {
				continue
			}
			if current_ray.y_error > 0 \
			&& current_ray.y_error <= current_ray.y_obscurity {
				continue
			}

			map_x := x + current_ray.x_relative
			map_y := y + current_ray.y_relative
			fov_set_visible_nc(fovmap, map_x, map_y, true, light_walls)
		}

		for i in 0 ..< len(fovmap.cells) {
			free(fov.raymap_grid[i])
		}
		delete(fov.raymap_grid)

		if light_walls {
			_postprocess_light_walls(fovmap, x, y, max_radius)
		}
	}
/*******************************************************************************/
