/**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**

		Ork Roguelike Kit

**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**/
#+feature dynamic-literals
package ork

import "base:runtime"
import "core:math/rand"
import "core:strings"
import "base:intrinsics"

import "core:slice"
import "core:time"

import rl "vendor:raylib"
import "utils/track"
import "utils/log"
import "utils"

// for convenience (internal logger)
__print      :: log.__print
__printf     :: log.__printf
__info       :: log.__info
__task       :: log.__task
__reminder   :: log.__reminder
__deprecated :: log.__deprecated
__warning    :: log.__warning
__error      :: log.__error
__error_quit :: log.__error_quit



@private internal : struct {
	user_init    : proc(),
	user_tick    : proc(),
	user_quit    : proc(),

	title        : string,

	running      : bool,
	screen_w     : int,
	screen_h     : int,
	bg_color     : Color,
	dt           : time.Duration,
	user_logger  : ^log.Logger,
	exit_key    : Keyboard_Key,

	main_console : ^Console,
	curr_camera  : ^Camera,
	default_font_layout : ^FontLayout,
	default_font_layout_name : string,

	default_font : ^Font,
	// error_image   : ^Image,
	// error_texture : k2.Texture,

	cameras       : [dynamic]^Camera,
	consoles      : [dynamic]^Console,
	fonts         : [dynamic]^Font,
	fovmaps       : [dynamic]^Fovmap,
	paths         : [dynamic]Path,
	rex_images    : [dynamic]^REX_Image,
	images        : [dynamic]rl.Image,
	map_gens      : [dynamic]^MapGen,
	noise_map_2ds : [dynamic]^NoiseMap2D,
	font_layouts  : map[string]^FontLayout,

	fps_history  : [250]int, // simple ringbuffer
	fps_index    : int,
	fps_average  : int,
	max_fps      : int,

	target_fps   : int,
	// exit_value   : int,

	rng_seed : u64,
	rng_state : rand.Default_Random_State,
	rng : runtime.Random_Generator,
}


start :: proc(init: proc(), tick: proc(), quit: proc() = proc() {}) {
	// defer os.exit(internal.exit_value)

	when ODIN_DEBUG {
		context.allocator = track.init()
		defer track.finish()  //ensure this is always called last
	}

	internal = {
		bg_color = {0, 0, 0, 255},
	// 	max_fps = 240,
		target_fps = 60,
		title = "Untitled Ork Game",

		user_init = init,
		user_tick = tick,
		user_quit = quit,

		exit_key = .Escape,

		default_font_layout_name = "cp437",
	}

	internal.rng_seed = u64(time.time_to_unix_nano(time.now()))
	internal.rng_state = rand.create(internal.rng_seed)
	internal.rng = rand.default_random_generator(&internal.rng_state)


	/************    Init Logger    ************/
	log.begin();
	defer log.end()
	internal.user_logger = log.new_logger()
	internal.user_logger.other_locations = true  // TODO: this needs a better name
	defer log.destroy_logger(internal.user_logger)
	log.get_current_logger().other_locations = false


	/************    Init Backend    ************/
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(800, 600, utils.to_cstr(internal.title))
	defer rl.CloseWindow()
	if !rl.IsWindowReady() do return

	rl.SetTargetFPS(i32(internal.target_fps))


	/************    Init Ork    ************/
	_init_everything()
	defer _end_everything()


	/************    Loop    ************/
	t1 := time.tick_now()
	internal.dt = time.Second / 60

	internal.running = true

	tex := rl.LoadTexture("assets/fonts/cp437_20x20.png")
	defer rl.UnloadTexture(tex)

	main_loop:
	for internal.running {
		frame_start := time.tick_now()
		// start_time := sdl.GetTicksNS()

		// calculate this at the end of the frame, so the first delta isn't
		// near zero, which severely imbalances the initial fps average
		defer internal.dt = time.tick_lap_time(&t1)

		// curr_fps := 1/time.duration_seconds(internal.dt)
		// internal.fps_history[internal.fps_index] = int(curr_fps)
		// internal.fps_index = int(math.wrap(f32(internal.fps_index+1), f32(len(internal.fps_history))))
		// sum :int
		// for fps in internal.fps_history do sum += fps
		// internal.fps_average = sum/len(internal.fps_history)


		/************    Input    ************/
		{
			if rl.WindowShouldClose() {
				internal.running = false
			}
			if !internal.running do break main_loop
			_input_begin_frame(internal.dt)
		}

		/************    Rendering    ************/
		rl.BeginDrawing()
		{
			rl.ClearBackground(internal.bg_color)
			internal.user_tick()
		}
		rl.EndDrawing()

		free_all(context.temp_allocator)
		when ODIN_DEBUG { track.check_bad_frees() }
	}
}


@private _init_everything :: proc() {
	_reset_fps_history()
	_init_default_font_layouts()

	img := new_image_from_memory(#load("res/default_font_16x16.png"))
	internal.default_font = new_font_from_image("default_font", img)

	// internal.error_image = _create_error_image()
	// internal.error_texture = k2.load_texture_from_bytes(internal.error_image.pixels)

	internal.user_init()

	// NOTE: if the user didn't create a console, do not continue, as there's
	// no console to infer the window size from.
	// Also, if internal.running == false, then the user requested exit
	// during init, so don't bother with this at all.
	if internal.main_console == nil && internal.running {
		__error_quit("A console must be created for the window size to be inferred.")
	}
}


@private _end_everything :: proc() {
	internal.user_quit()
	_input_destroy()

	internal.main_console = nil // make this nil to allow freeing it

	_destroy_all_paths()
	_destroy_all(&internal.images,        delete_image)
	_destroy_all(&internal.rex_images,    rex_delete_image)
	_destroy_all(&internal.map_gens,      delete_mapgen)
	_destroy_all(&internal.consoles,      delete_console)
	_destroy_all(&internal.noise_map_2ds, delete_noise_map_2d)
	_destroy_all(&internal.fovmaps,       delete_fov)
	_destroy_all(&internal.fonts,         delete_font)
	_destroy_all(&internal.cameras,       delete_camera)
	_free_all_font_layouts()
}


@private _resize_window :: proc() {
	assert(internal.main_console != nil)

	c := internal.main_console
	cw, ch := get_cell_size(c)

	mw := int(rl.GetMonitorWidth(rl.GetCurrentMonitor()))
	mh := int(rl.GetMonitorHeight(rl.GetCurrentMonitor()))

	w := c.w * cw
	h := c.h * ch
	internal.screen_w = w
	internal.screen_h = h
	px := i32(f32(mw - w) / 2.0)
	py := i32(f32(mh - h) / 2.0)

	if w > mw do px = 0
	if h > mh do py = 0

	// set position first to avoid occasional weird effects
    rl.SetWindowSize(i32(internal.screen_w), i32(internal.screen_h))
	rl.SetWindowPosition(px, py)
}


@private _reset_fps_history :: proc() {
	// Fill the fps_history with whatever the refresh rate is

	// TODO: get refresh rate if vsync is on, else get fps_cap.
	//       Using 60 for now.

	for i in 0 ..< len(internal.fps_history) {
		internal.fps_history[i] = 60
	}
}


@private _destroy_all_paths :: proc() {
	for len(internal.paths) > 0 {
		path := internal.paths[0]
		switch p in path {
			case ^Dijkstra_Map: delete_dijkstra(p)
			case ^AStar:        delete_astar(p)
		}
	}
	delete(internal.paths)
}


@private _get_item_index :: proc(array:[]$A, item: $B) -> (int, bool) {
	return slice.linear_search(array[:], item)
}


@private _destroy_all :: proc(array: ^[dynamic]$T,
                              free_proc: proc(item: T, loc := #caller_location),
                              loc := #caller_location
                             ) where intrinsics.type_is_comparable(T) {
	for len(array) > 0 {
		free_proc(array[0], loc)
	}
	delete(array^)
}




/*******************************************************************************

		Misc

*******************************************************************************/
// Request Ork to shutdown and exit.
exit :: proc(exit_value := 0) {
	internal.running = false
	// internal.exit_value = exit_value
}

// Returns the frame's delta-time
get_delta_time :: proc() -> f64 {
	return time.duration_seconds(internal.dt)
}

// Returns the current frame-rate (frames per second).
get_fps :: proc() -> int {
	return int(1 / time.duration_seconds(internal.dt))
}

// Returns the current frame-rate, smoothed, to prevent drastic
// fluctuations. This is ideal for displaying the FPS on the screen.
get_fps_smoothed :: proc() -> int {
	return internal.fps_average
}

// (NIY) Set the title of the window.
set_window_title :: proc(title: string) {
	// TODO
	internal.title = title
	rl.SetWindowTitle(utils.to_cstr(title))
}

// (NIY) Enable or disable v-sync.
set_vsync :: proc(enable: bool) {
	// TODO
}

// (NIY) Set a maximum cap for the frame-rate.
set_fps_cap :: proc(max_fps: int) {
	if max_fps < 0 do return
	internal.max_fps = max_fps
	_reset_fps_history()
}


get_exit_key :: proc() -> Keyboard_Key {
	return internal.exit_key
}

set_exit_key :: proc(key: Keyboard_Key) {
	internal.exit_key = key
	rl.SetExitKey(rl.KeyboardKey(key))
}

get_screen_mouse_position :: proc() -> Vec2 {
	pos := transmute(Vec2f) rl.GetMousePosition()
	// return Vec2{int(pos.x), int(pos.y)}
	return Vec2(pos)
}


set_main_console :: proc(c: ^Console) {
	if c == internal.main_console do return
	lc := internal.main_console // last main console
	internal.main_console = c

	// if this is true, we're either still in init or shutdown,
	// so no need to do anything else
	if !internal.running do return

	if c.w != lc.w || c.h != lc.h \
	|| c._font.tw != lc._font.tw || c._font.th != lc._font.th {
		_resize_window()
	}
}


// Returns the length of a string in runes
string_len :: proc(text: string) -> int {
	return strings.rune_count(text)
}



/*******************************************************************************

		Camera

*******************************************************************************/
Camera :: struct {
	_viewport : Rect,  // Camera's viewport rectangle in screen-space.
	_pos      : Vec2,  // Camera's position in world-space.
	_min      : Vec2,  // Camera's movement limits
	_max      : Vec2,  // in world-space.
}

// Creates a new camera object based on the given viewport size
new_camera :: proc{
	new_camera_from_coords,
	new_camera_from_rect,
}

// Creates a new camera object, specifying the viewport size as coordinate values
new_camera_from_coords :: proc(x, y, w, h: int) -> ^Camera {
	cam := _create_camera_from_coords(x, y, w, h)
	append(&internal.cameras, cam)
	return cam
}

// Create a new camera, specifying the viewport size as a Rect
new_camera_from_rect :: proc(viewport_rect: Rect) -> ^Camera {
	cam := _create_camera_from_rect(viewport_rect)
	append(&internal.cameras, cam)
	return cam
}

// Deletes the given `camera` and frees its memory.
delete_camera :: proc(camera: ^Camera, loc := #caller_location) {
	if camera == nil do return
	idx, ok := _get_item_index(internal.cameras[:], camera)
	if ok do unordered_remove(&internal.cameras, idx)
	_free_camera(camera)
}


@private _create_camera_from_coords :: proc(x, y, w, h: int) -> ^Camera {
	return _create_camera_from_rect( Rect{x, y, w, h} )
}


@private _create_camera_from_rect :: proc(viewport_rect: Rect) -> ^Camera {
	cam := new(Camera)
	cam._viewport = viewport_rect
	cam._min = {-999999, -999999}
	cam._max = {999999, 999999}
	return cam
}



@private _free_camera :: proc(cam: ^Camera) {
	free(cam)
}


// Begin camera transformations. Drawing to a console in between 'begin_camera'
// and 'end_camera' will automatically account for this camera's position
// in world-space.
begin_camera :: proc(cam: ^Camera) {
	internal.curr_camera = cam
}

// End camera transformations.
end_camera :: proc() {
	internal.curr_camera = nil
}


// Set the viewport of this camera. This is the part of the screen where
// drawing can take place. Nothing will be drawn outside of this rectangle.
camera_set_viewport :: proc {
	camera_set_viewport_coords,
	camera_set_viewport_rect,
}

camera_set_viewport_coords :: proc(cam: ^Camera, x, y, w, h: int) {
	cam._viewport = Rect{x, y, w, h}
}

camera_set_viewport_rect :: proc(cam: ^Camera, rect: Rect) {
	cam._viewport = rect
}


// set the camera's movement limits. The camera's position is clamped
// to these limits.
camera_set_limits :: proc(cam: ^Camera, min, max: Vec2) {
	cam._min = min
	cam._max = max
}


// Move camera to a position in world-space, taking the limits into account.
camera_set_position :: proc {
	camera_set_position_xy,
	camera_set_position_vec,
}

camera_set_position_xy :: proc(cam: ^Camera, #any_int x, y: int) {
	camera_set_position_vec(cam, {x, y})
}

camera_set_position_vec :: proc(cam: ^Camera, pos: Vec2) {
	// TODO: should the viewport really be in this equation? This seems to be
	// working fine, but it's mixing screen and world coords.
	cam._pos = Vec2 {
		max(cam._min.x, min(pos.x - cam._viewport.w / 2, cam._max.x - cam._viewport.w)),
		max(cam._min.y, min(pos.y - cam._viewport.h / 2, cam._max.y - cam._viewport.h)),
	}
}


// check if a screen-space position is within the camera's viewport.
camera_is_in_viewport :: proc {
	camera_is_in_viewport_vec,
	camera_is_in_viewport_xy,
}

camera_is_in_viewport_vec :: proc(cam: ^Camera, pos: Vec2) -> bool {
	return camera_is_in_viewport_xy(cam, pos.x, pos.y)
}

camera_is_in_viewport_xy :: proc(cam: ^Camera, x, y: int) -> bool {
	return x >= cam._viewport.x  \
	    && y >= cam._viewport.y  \
	    && x <  cam._viewport.x+cam._viewport.w  \
	    && y <  cam._viewport.y+cam._viewport.h
}

// check if screen-space 'x' is within the camera's viewport.
camera_is_in_viewport_x :: proc(cam: ^Camera, x: int) -> bool {
	return x >= cam._viewport.x && x < cam._viewport.x+cam._viewport.w
}

// check if screen-space 'y' is within the camera's viewport.
camera_is_in_viewport_y :: proc(cam: ^Camera, y: int) -> bool {
	return y >= cam._viewport.y && y < cam._viewport.y+cam._viewport.h
}

// Returns the world-space rectangle that is visible to the camera
camera_get_visible_world_rect :: proc(cam: ^Camera) -> Rect {
	return Rect{cam._pos.x, cam._pos.y, cam._viewport.w, cam._viewport.h}
}


// Convert world-space coordinates to screen-space coordinates
camera_to_screen :: proc(cam: ^Camera, #any_int x, y: int) -> (int, int) {
	sx := x - cam._pos.x + cam._viewport.x
	sy := y - cam._pos.y + cam._viewport.y
	return sx, sy
}

// Convert world-space coordinates to screen-space coordinates. Returns a Vec2.
camera_to_screen_v :: proc(cam: ^Camera, #any_int x, y: int) -> Vec2 {
	sx, sy := camera_to_screen(cam, x, y)
	return {sx, sy}
}


// Convert world-space 'x' to screen-space 'x'
camera_to_screen_x :: proc(cam: ^Camera, mx: int) -> int {
	return mx - cam._pos.x + cam._viewport.x
}

// Convert world-space 'y' to screen-space 'y'.
camera_to_screen_y :: proc(cam: ^Camera, my: int) -> int {
	return my - cam._pos.y + cam._viewport.y
}


// Convert screen-space coordinates to world-space coordinates.
camera_to_world :: proc(cam: ^Camera, #any_int x, y: int) -> (int, int) {
	wx := cam._pos.x - cam._viewport.x + x
	wy := cam._pos.y - cam._viewport.y + y
	return x, y
}

// Convert screen-space coordinates to world-space coordinates. Returns a Vec2.
camera_to_world_vec :: proc(cam: ^Camera, #any_int x, y: int) -> Vec2 {
	wx, wy := camera_to_world(cam, x, y)
	return {x, y}
}

// Convert screen-space 'x' to world-space 'x'
camera_to_world_x :: proc(cam: ^Camera, cx: int) -> int {
	return cam._pos.x - cam._viewport.x + cx
}

// Convert screen-space 'y' to world-space 'y'
camera_to_world_y :: proc(cam: ^Camera, cy: int) -> int {
	return cam._pos.y - cam._viewport.y + cy
}






/*******************************************************************************

	Logging procs that make sure the 'user_logger' is always used.
	(Users can feel free to ignore this logger if they want.)

*******************************************************************************/
print :: proc(args: ..any, loc := #caller_location) {
	log.print(logger=internal.user_logger, args=args, loc=loc)
}

printf :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.printf(logger=internal.user_logger, msg=msg, args=args, loc=loc)
}

info :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.info(logger=internal.user_logger, msg=msg, args=args, loc=loc)
}

task :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.task(logger=internal.user_logger, msg=msg, args=args, loc=loc)
}

reminder :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.reminder(logger=internal.user_logger, msg=msg, args=args, loc=loc)
}

deprecated :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.deprecated(logger=internal.user_logger, msg=msg, args=args, loc=loc)
}

warning :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.warning(logger=internal.user_logger, msg=msg, args=args, loc=loc)
}

error :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.error(logger=internal.user_logger, msg=msg, args=args, loc=loc)
}

// import "core:os/os2"
error_quit :: proc(msg:string, args: ..any, loc := #caller_location) {
	log.error(logger=internal.user_logger, msg=msg, args=args, loc=loc)
	// os2.exit(1)
	internal.running = false
	// internal.exit_value = 1
}






/*******************************************************************************

		REX_Image

*******************************************************************************/
import rex "libs/rexpaint_odin"

/*
	REXPaint image loading
	- https://www.gridsagegames.com/rexpaint
*/

REX_Color  :: rex.Color
REX_Cell   :: rex.Cell
REX_Layer  :: rex.Layer
REX_Image  :: rex.Image

REX_PINK   :: rex.PINK
REX_TRANSP :: rex.TRANSP
REX_BLACK  :: rex.BLACK

// Loads a `REX_Image` from `file_path`.
rex_load_image :: proc(file_path: string) -> ^REX_Image {
	img := rex.load_image(file_path)
	append(&internal.rex_images, img)
	return img
}

// Creates a new, empty `REX_Image` of `w, h` size, with `num_layers` layers.
rex_new_image :: proc(#any_int w, h, num_layers: int, version: Maybe(int) = nil) -> ^REX_Image {
	v, _ := version.?
	img := rex.new_image(w, h, num_layers, v)
	append(&internal.rex_images, img)
	return img
}

// Destroys a `REX_Image` and frees its memory.
rex_delete_image :: proc(img: ^REX_Image, loc := #caller_location) {
	idx, ok := _get_item_index(internal.rex_images[:], img)
	if ok do unordered_remove(&internal.rex_images, idx)
	rex.unload_image(img)
}


// Returns whether two `REX_Image`s are the same.
rex_is_equal :: rex.is_equal

// Returns whether the given position and layer are within bounds of the `REX_Image`.
rex_is_in_bounds :: rex.is_in_bounds


// Clears the given `REX_Image`.
rex_clear :: rex.clear

// Clears the given layer of a `REX_Image`.
rex_clear_layer :: rex.clear_layer

// Merge layers down from `top` to `bottom`.
rex_merge_layers :: rex.merge_layers


// Sets the properties of a cell of a `REX_Image`.
rex_set_cell :: rex.set_cell


// Returns the `REX_Cell` at the given coordinates.
rex_get_cell :: rex.get_cell

// Returns the glyph at the given coordinates.
rex_get_glyph :: rex.get_glyph

// Returns the foreground color at the given coordinates.
rex_get_fg :: rex.get_fg

// Returns the background color at the given coordinates.
rex_get_bg :: rex.get_bg


// Returns whether the cell at the given position and layer is transparent.
rex_is_transparent :: rex.is_transparent

// Returns whether the given `REX_Cell` is transparent.
rex_is_transparent_cell :: rex.is_transparent_cell







