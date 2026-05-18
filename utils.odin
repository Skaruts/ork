package ork


import "core:math"
import "core:math/rand"
import "core:os"
import stbi "vendor:stb/image"

import k2 "libs/karl2d"


DEG2RAD :: math.PI / 180
RAD2DEG :: 180 / math.PI


/*******************************************************************************

		Vector2

*******************************************************************************/
Vec2    :: [2]int
Vec2f   :: k2.Vec2

VEC2_ZERO  :: Vec2{}
VEC2_ONE   :: Vec2{ 1,  1}
VEC2_LEFT  :: Vec2{-1,  0}
VEC2_RIGHT :: Vec2{ 1,  0}
VEC2_UP    :: Vec2{ 0, -1}
VEC2_DOWN  :: Vec2{ 0,  1}


// TODO: vector math stuff



// clockwise directions
Direction :: enum {
	North,
	East,
	South,
	West,
	North_East,
	South_East,
	South_West,
	North_West,
}

DirectionSet :: distinct bit_set[Direction]


// clockwise directions vectors
VEC2_NORTH      :: Vec2{ 0, -1}
VEC2_EAST       :: Vec2{ 1,  0}
VEC2_SOUTH      :: Vec2{ 0,  1}
VEC2_WEST       :: Vec2{-1,  0}
VEC2_NORTH_EAST :: Vec2{ 1, -1}
VEC2_SOUTH_EAST :: Vec2{ 1,  1}
VEC2_SOUTH_WEST :: Vec2{-1,  1}
VEC2_NORTH_WEST :: Vec2{-1, -1}


// directions array
@(rodata)
DIRECTIONS := [Direction]Vec2 {
	.North      = VEC2_NORTH,
	.East       = VEC2_EAST,
	.South      = VEC2_SOUTH,
	.West       = VEC2_WEST,
	.North_East = VEC2_NORTH_EAST,
	.South_East = VEC2_SOUTH_EAST,
	.South_West = VEC2_SOUTH_WEST,
	.North_West = VEC2_NORTH_WEST,
}


get_random_direction :: proc(diagonals: bool) -> Vec2 {
	idx := rand.int_max( diagonals ? len(DIRECTIONS) : len(DIRECTIONS)/2  )
	return DIRECTIONS[ Direction(idx) ]
}

/*******************************************************************************

		Rect

*******************************************************************************/
Rect  :: struct {x, y, w, h: int}
Rectf :: k2.Rect

rectf_intersects :: proc(a, b: Rectf) -> bool {
	return a.x < b.x+b.w && a.x+a.w > b.x \
		&& a.y < b.y+b.h && a.y+a.h > b.y
}

rect_intersects :: proc(a, b: Rect) -> bool {
	return rectf_intersects(
		Rectf{f32(a.x), f32(a.y), f32(a.w), f32(a.h)},
		Rectf{f32(b.x), f32(b.y), f32(b.w), f32(b.h)}
	)
}


rectf_touches :: proc(a, b: Rectf) -> bool {
	return a.x <= b.x+b.w && a.x+a.w >= b.x \
		&& a.y <= b.y+b.h && a.y+a.h >= b.y
}

rect_touches :: proc(a, b: Rect) -> bool {
	return rectf_touches(
		Rectf{f32(a.x), f32(a.y), f32(a.w), f32(a.h)},
		Rectf{f32(b.x), f32(b.y), f32(b.w), f32(b.h)}
	)
}


// TODO: rectangle stuff



/*******************************************************************************

		Random

*******************************************************************************/
randf :: proc {
	randf_default,
	randf_range,
}

randf_default :: proc() -> f64 {
	return rand.float64()
}

randf_range :: proc(min, max: f64) -> f64 {
	return rand.float64_range(min, max)
}

rand :: proc {
	rand_default,
	rand_range,
}

rand_default :: proc(max: uint, gen := context.random_generator) -> uint {
	return rand.uint_max(max, gen)
}

rand_range :: proc(min, max: uint, gen := context.random_generator) -> uint {
	return rand.uint_range(min, max, gen)
}




/*******************************************************************************

		Image

*******************************************************************************/
CHANNELS :: 4

Image :: struct {
	w, h: int,
	pixels: []byte,
}


new_image :: proc {
	new_image_empty,
	new_image_from_file,
	new_image_from_memory,
}

new_image_empty :: proc(w, h: int/*, color: Maybe(Color)*/) -> ^Image {
	img := _create_image_empty(w, h)
	append(&internal.images, img)
	return img
}

new_image_from_file :: proc(img_path: string) -> ^Image {
	img := _create_image_from_file(img_path)
	append(&internal.images, img)
	return img
}

new_image_from_memory :: proc(bytes: []byte) -> ^Image {
	img := _create_image_from_memory(bytes)
	append(&internal.images, img)
	return img
}

delete_image :: proc(img: ^Image, loc := #caller_location) {
	if img == nil do return
	idx, ok := _get_item_index(internal.images[:], img)
	if ok do unordered_remove(&internal.images, idx)
	if len(img.pixels) == 0 do return
	_free_image(img)
}


image_blit_rect :: proc(src_img, dst_img: ^Image, src_rect: Rect, dst_pos: Vec2, tint: Color) {
	w := src_rect.w
	h := src_rect.h
	p := dst_pos

	for j in 0 ..< h {
		for i in 0 ..< w {
			x := src_rect.x + i
			y := src_rect.y + j
			dx := p.x + i
			dy := p.y + j
			if x < 0 || y < 0 || x >= src_img.w || y >= src_img.h do continue
			if dx < 0 || dy < 0 || dx >= dst_img.w || dy >= dst_img.h do continue

			sidx := (x+y*src_img.w)*CHANNELS
			didx := (dx+dy*dst_img.w)*CHANNELS
			dst_img.pixels[didx+0] = u8( (int(src_img.pixels[sidx+0]) * int(tint.r) ) / 255 )
			dst_img.pixels[didx+1] = u8( (int(src_img.pixels[sidx+1]) * int(tint.g) ) / 255 )
			dst_img.pixels[didx+2] = u8( (int(src_img.pixels[sidx+2]) * int(tint.b) ) / 255 )
			dst_img.pixels[didx+3] = u8( (int(src_img.pixels[sidx+3]) * int(tint.a) ) / 255 )
		}
	}
}


// TODO: support optional color
@private _create_image_empty :: proc(w, h: int/*, color: Maybe(Color)*/) -> ^Image {
	img := new(Image)
	img.w = w
	img.h = h
	img.pixels = make([]byte, w*h*CHANNELS)
	return img
}


@private _create_image_from_file :: proc(img_path: string) -> ^Image {
	img := _load_image_file(img_path)
	return img
}

@private _create_image_from_memory :: proc(bytes: []byte) -> ^Image {
	img := _load_image_memory(bytes)
	return img
}

@private _free_image :: proc(img: ^Image, loc := #caller_location) {
	stbi.image_free(raw_data(img.pixels))
	free(img)
}


@private _allocate_image_empty :: proc(w, h: int, allocator := context.allocator) -> ^Image {
	img := new(Image)
	img.w = w
	img.h = h
	img.pixels = make([]byte, w*h*CHANNELS, allocator)
	return img
}

@private _deallocate_image :: proc(img: ^Image, allocator := context.allocator) {
	delete(img.pixels, allocator)
	free(img)
}

@private _load_image_memory :: proc(bytes: []byte) -> ^Image {
	img := new(Image)

    original_channels: i32
    w, h: i32
    pixels := stbi.load_from_memory(
	    raw_data(bytes), i32(len(bytes)),
	    &w, &h, &original_channels, CHANNELS
	)

	img.w = int(w)
	img.h = int(h)
	img.pixels = pixels[ : w*h*CHANNELS ]
    return img
}

@private _load_image_file :: proc(fullpath: string) -> (^Image, bool) #optional_ok {
	img: ^Image
    content, err := os.read_entire_file(fullpath, context.temp_allocator)
    if err == nil {
    	img = _load_image_memory(content)
	    return img, true
    }

    return img, false
}



/*******************************************************************************

		Shapes (as arrays of points)

*******************************************************************************/
// Bresenham's line (returns a list of points that make up the line)
line_points :: proc(x1, y1, x2, y2: int, exclude_start := false, allocator := context.temp_allocator) -> [dynamic]Vec2 {
	x1, y1, x2, y2 := x1, y1, x2, y2

	points := make([dynamic]Vec2, allocator)

	err : int = 0
	dx  : int = x2 - x1
	dy  : int = y2 - y1
	ix  : int = dx > 0 ? 1 : -1
	iy  : int = dy > 0 ? 1 : -1

	dx = 2 * abs(dx)
	dy = 2 * abs(dy)


	if ! exclude_start {
		append(&points, Vec2{x1, y1})
	}

	if dx >= dy {
		err = dy - dx / 2
		for x1 != x2 {
			if err > 0 || (err == 0 && ix > 0) {
				err -= dx
				y1 += iy
			}
			err += dy
			x1  += ix
			append(&points, Vec2{x1, y1})
		}
	} else {
		err = dx - dy / 2
		for y1 != y2 {
			if err > 0 || (err == 0 && iy > 0) {
				err -= dy
				x1 += ix
			}
			err += dx
			y1 += iy
			append(&points, Vec2{x1, y1})
		}
	}
	return points
}


rect_points :: proc(x, y, w, h: int, allocator := context.temp_allocator) -> [dynamic]Vec2 {
	points := make([dynamic]Vec2, allocator)
	for i in 0 ..< w {
		append(&points, Vec2{x+i, y    })
		append(&points, Vec2{x+i, y+h-1})
	}
	for j in 1 ..< h-1 {
		append(&points, Vec2{x,     y+j})
		append(&points, Vec2{x+w-1, y+j})
	}
	return points
}

rect_filled_points :: proc(x, y, w, h: int, allocator := context.temp_allocator) -> [dynamic]Vec2 {
	points := make([dynamic]Vec2, allocator)
	for j in 0 ..< h {
		for i in 0 ..< w {
			append(&points, Vec2{x+i, y+j})
		}
	}
	return points
}


// mid-point circle something, I forgot where I got this
circle_points :: proc(x, y, r: int, allocator := context.temp_allocator) -> [dynamic]Vec2 {
	points := make([dynamic]Vec2, allocator)
	r := r

	dx  : int = -r
	dy  : int = 0
	err : int = 1-2*r // 2-2*r

	for {
		if dx >= 0 do break

		append(&points, Vec2{x-dx, y+dy})
		append(&points, Vec2{x-dy, y-dx})
		append(&points, Vec2{x+dx, y-dy})
		append(&points, Vec2{x+dy, y+dx})

		r = err
		if r <= dy {
			dy  += 1
			err += (dy * 2 + 1)
		}

		if r > dx || err > dy {
			dx  += 1
			err += (dx * 2 + 1)
		}
	}

	return points
}


circle_filled_points :: proc(x, y, r: int, allocator := context.temp_allocator) -> [dynamic]Vec2 {
	points := make([dynamic]Vec2, allocator)
	r := r

	dx  : int = -r
	dy  : int = 0
	err : int = 1-2*r // 2-2*r

	for {
		// NOTE: this should be '>=', but circles with radius 1 were missing the
		// bottom part. Using '>' fixes it, and doesn't seem to cause issues,
		// but may need more testing.
		if dx > 0 do break

		for i in x+dx ..= x-dx {
			append(&points, Vec2{i, y+dy})
		}

		for i in x-dy ..= x+dy {
			append(&points, Vec2{i, y+dx})
		}

		r = err
		if r <= dy {
			dy  += 1
			err += (dy * 2 + 1)
		}

		if r > dx || err > dy {
			dx  += 1
			err += (dx * 2 + 1)
		}
	}

	return points
}


// based on:
//     http://members.chello.at/easyfilter/bresenham.html
ellipse_points :: proc(x, y, rx, ry: int, allocator := context.temp_allocator) -> [dynamic]Vec2 {
	points := make([dynamic]Vec2, allocator)
	if rx == 0 || ry == 0 do return points

	x1, y1, x2, y2 := x-rx, y-ry, x+rx, y+ry

	a   := abs(x2-x1) // values of diameter
	b   := abs(y2-y1)
	b1  := b << 1
	dx  := 4*(1-a)*b*b
	dy  := 4*(b1+1)*a*a
	err := dx+dy+b1*a*a  // error increment
	e2 : int = 0

	y1 += (b+1) / 2
	y2 -= b1   // starting pixel
	a  *= 8 * a
	b1 =  8 * b * b

	for {
		append(&points, Vec2{x2, y1})   //   I. Quadrant
		append(&points, Vec2{x1, y1})   //  II. Quadrant
		append(&points, Vec2{x1, y2})   // III. Quadrant
		append(&points, Vec2{x2, y2})   //  IV. Quadrant

		e2 = err*2
		if e2 <= dy {  // y step
			y1  += 1
			y2  -= 1
			dy  += a
			err += dy
		}
		if e2 >= dx || err*2 > dy {  // x step
			x1  += 1
			x2  -= 1
			dx  += b1
			err += dx
		}
		if x1 > x2 do break
	}

	for y1-y2 < b {
		// too early stop of flat ellipses a = 1
		append(&points, Vec2{x1-1, y1})  // -> finish tip of ellipse
		append(&points, Vec2{x2+1, y1})
		append(&points, Vec2{x1-1, y2})
		append(&points, Vec2{x2+1, y2})

		y1 += 1
		y2 -= 1
	}

	return points
}

