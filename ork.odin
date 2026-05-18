/**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**

		Ork Roguelike Kit

**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**//**/
#+feature dynamic-literals
package ork

import "base:intrinsics"

import "core:slice"
import "core:fmt"
import "core:os"
import "core:time"

import k2 "libs/karl2d"
import "utils/track"
import "utils/log"


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

	k2_state     : ^k2.State,
	title        : string,

	running      : bool,
	screen_w     : int,
	screen_h     : int,
	bg_color     : Color,
	dt           : time.Duration,
	user_logger  : ^log.Logger,
	panic_key    : Keyboard_Key,

	main_console : ^Console,
	curr_camera  : ^Camera,
	default_font_layout : ^FontLayout,
	default_font_layout_name : string,

	// error_image   : ^Image,
	// error_texture : k2.Texture,

	cameras      : [dynamic]^Camera,
	consoles     : [dynamic]^Console,
	fonts        : [dynamic]^Font,
	fovmaps      : [dynamic]^Fovmap,
	paths        : [dynamic]Path,
	rex_images   : [dynamic]^REX_Image,
	images       : [dynamic]^Image,
	map_gens     : [dynamic]^MapGen,
	font_layouts : map[string]^FontLayout,

	fps_history  : [250]int, // simple ringbuffer
	fps_index    : int,
	fps_average  : int,
	max_fps      : int,

	exit_value   : int,
}


start :: proc(init: proc(), tick: proc(), quit: proc() = proc() {}) {
	defer os.exit(internal.exit_value)

	when ODIN_DEBUG {
		context.allocator = track.init()
		defer track.finish()  //ensure this is always called last
	}

	internal = {
		bg_color = {0, 0, 0, 255},
	// 	max_fps = 240,
		title = "Untitled Ork Game",

		user_init = init,
		user_tick = tick,
		user_quit = quit,

		panic_key = .Escape,

		default_font_layout_name = "cp437",
	}


	/************    Init Logger    ************/
	log.begin();
	defer log.end()
	internal.user_logger = log.new_logger()
	internal.user_logger.other_locations = true  // TODO: this needs a better name
	defer log.destroy_logger(internal.user_logger)
	log.get_current_logger().other_locations = true


	/************    Init Karl2D    ************/
	// TODO: might be better to init the window hidden
	// and then show it after size being set (after 'user_init')
	// The size here is just a placeholder.
	internal.k2_state = k2.init(1280, 720, internal.title, {
		disable_auto_scale_hint = true,  // TODO: figure out how to work with this
	})
	defer k2.shutdown()

	// window_scale := k2.get_window_scale()


	/************    Init Ork    ************/
	_init_everything()
	defer _end_everything()


	/************    Loop    ************/
	t1 := time.tick_now()
	internal.dt = time.Second / 60

	internal.running = true

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
			if !k2.update() || k2.key_went_down(internal.panic_key) {
				internal.running = false
			}
			if !internal.running do break main_loop
			_input_begin_frame(internal.dt)
		}

		/************    Rendering    ************/
		{
			k2.clear(internal.bg_color)

			internal.user_tick()
		}
		k2.present()

		free_all(context.temp_allocator)
		when ODIN_DEBUG { track.check_bad_frees() }
	}
}


@private _init_everything :: proc() {
	_reset_fps_history()
	_init_default_font_layouts()

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
	_destroy_all(&internal.images,     delete_image)
	_destroy_all(&internal.rex_images, rex_delete_image)
	_destroy_all(&internal.map_gens,   delete_mapgen)
	_destroy_all(&internal.consoles,   delete_console)
	_destroy_all(&internal.fovmaps,    delete_fov)
	_destroy_all(&internal.fonts,      delete_font)
	_destroy_all(&internal.cameras,    delete_camera)
	_free_all_font_layouts()
}


@private _resize_window :: proc() {
	assert(internal.main_console != nil)
	c := internal.main_console
	cw, ch := get_cell_size(c)
	w := c.w * cw
	h := c.h * ch
	internal.screen_w = w
	internal.screen_h = h

	__print(w, h)
	k2.set_screen_size(internal.screen_w, internal.screen_h)

	// NOTE: K2 doesn't provide the monitor size yet, so it has to be hardcoded
	// for now. This is for centering the window.
	mw, mh := 1920, 1080
	k2.set_window_position(mw/2-w/2, mh/2-h/2 - 50) // subtract about 50 to account for taskbar (on Windows)

	// TODO: something equivalent to this
	// sdl.SetRenderLogicalPresentation(internal.renderer, internal.screen_w, internal.screen_h, .INTEGER_SCALE)
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
            ) {
	for len(array) > 0 {
		free_proc(array[len(array)-1], loc)
	}
	delete(array^)
}




/*******************************************************************************

		Misc

*******************************************************************************/
// Request Ork to shutdown and exit.
exit :: proc(exit_value := 0) {
	internal.running = false
	internal.exit_value = exit_value
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


get_panic_key :: proc() -> Keyboard_Key {
	return internal.panic_key
}

set_panic_key :: proc(key: Keyboard_Key) {
	internal.panic_key = key
}

get_screen_mouse_position :: proc() -> Vec2 {
	pos := k2.get_mouse_position()
	return Vec2{int(pos.x), int(pos.y)}
}


set_main_console :: proc(c: ^Console) {
	if c.id == internal.main_console.id do return
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



/*******************************************************************************

		Font

*******************************************************************************/
// A bitmap font or tileset
Font :: struct {
	name       : string,
	cols, rows : int,         // width/height of the font in columns/rows
	tw, th     : int,         // tile width / height
	texture    : k2.Texture,
	layout     : string,
	image      : ^Image,
}


// Creates a new font from a bitmap font file, optionally with a `name` and a
// `layout_name`.
new_font :: proc {
	new_font_filepath,
	new_font_with_name,
	new_font_from_image,
}

// Creates an unnamed new font from a bitmap font file, optionally with a
// `layout_name`.
new_font_filepath :: proc(file_path: string,
                             layout_name:=internal.default_font_layout_name
                        ) -> ^Font {
	font := _create_font_filepath(file_path, layout_name)
	append(&internal.fonts, font)
	return font
}

// Creates a named new font from a bitmap font file, optionally with a
// `layout_name`.
new_font_with_name :: proc(name: string, file_path: string,
                          layout_name:=internal.default_font_layout_name
                    ) -> ^Font {
	font := _create_font_with_name(name, file_path, layout_name)
	append(&internal.fonts, font)
	return font
}

// Creates a new font from an `Image` object.
new_font_from_image :: proc(name: string, img: ^Image,
                            layout_name:=internal.default_font_layout_name
                        ) -> ^Font {
	font := _create_font_from_image(name, img, layout_name)
	append(&internal.fonts, font)
	return font
}

// Deletes the given `font` and frees its memory.
delete_font :: proc(font: ^Font, loc := #caller_location) {
	if font == nil do return
	idx, ok := _get_item_index(internal.fonts[:], font)
	if ok do unordered_remove(&internal.fonts, idx)
	_free_font(font)
}





@private _create_font_filepath :: proc(file_path: string, layout_name:=internal.default_font_layout_name) -> ^Font {
	return _create_font_with_name("", file_path, layout_name)
}

@private _create_font_with_name :: proc(name: string, file_path: string, layout_name:=internal.default_font_layout_name) -> ^Font {
	img := new_image_from_file(file_path)
	return _create_font_from_image(name, img, layout_name)
}

@private _create_font_from_image :: proc(name: string, img: ^Image, layout_name:=internal.default_font_layout_name) -> ^Font {
	layout := _get_font_layout(layout_name)
	tex, img := _load_font_texture(img)

	cols := 16
	rows := 16

	tw := int(tex.width)  / layout.cols
	th := int(tex.height) / layout.rows

	font := new(Font)
	font.name      = name != "" ? name : "Unnamed Font"
	font.cols      = layout.cols
	font.rows      = layout.rows
	font.texture   = tex
	font.image     = img
	font.tw        = tw
	font.th        = th
	font.layout    = layout_name

	return font
}


@private _free_font :: proc(font: ^Font) {
	k2.destroy_texture(font.texture)
	free(font)
}


@private _load_font_texture :: proc(img: ^Image) -> (k2.Texture, ^Image) {
	font_tex: k2.Texture

	if len(img.pixels) == 0 do return font_tex, img

	for i in 0 ..< img.w*img.h {
		idx := i*CHANNELS
		pixel := Color {
			img.pixels[idx+0],
			img.pixels[idx+1],
			img.pixels[idx+2],
			img.pixels[idx+3],
		}

		if pixel != WHITE {
			img.pixels[idx+0] = 0
			img.pixels[idx+1] = 0
			img.pixels[idx+2] = 0
			img.pixels[idx+3] = 0
		}
	}

	font_tex = k2.load_texture_from_bytes_raw(img.pixels, int(img.w), int(img.h), .RGBA_8_Norm)
	return font_tex, img
}





/*******************************************************************************

		Font Layouts

*******************************************************************************/
// The "cp437" codepage layout name.
CP437 :: "cp437"
// LibTCOD's font layout.
TCOD :: "tcod"
// (NIY) Represents the "cp860" codepage layout name.
// CP860 :: "cp860"     // portuguese


DEFAULT_FONT_LAYOUT_NAME :: "cp437"


// A specification of how a font is laid out (e.g. cp437)
FontLayout :: struct {
	name                  : string,
	cols, rows            : int,
	indices_by_char       : map[Rune]Index,
	indices_by_codepoints : map[uint]Index,
	chars_by_index        : map[Index]Rune,
}


// Converts `codepoint` into its respective tile-index, based on the given
// console or font.
codepoint_to_index :: proc{
	font_codepoint_to_index,
	console_codepoint_to_index
}

// Converts `char` into its respective tile-index, based on the given
// console or font.
char_to_index      :: proc{
	font_char_to_index,
	console_char_to_index
}

// Converts `index` into its respective char (rune), based on the given
// console or font.
index_to_char      :: proc{
	font_index_to_char,
	console_index_to_char
}


font_codepoint_to_index :: proc(font: ^Font, codepoint: uint) -> Index {
	return _layout_codepoint_to_index(font.layout, codepoint)
}

font_char_to_index :: proc(font: ^Font, char: Rune) -> Index {
	return _layout_char_to_index(font.layout, char)
}

font_index_to_char :: proc(font: ^Font, index: Index) -> Rune {
	return _layout_index_to_char(font.layout, index)
}



console_codepoint_to_index :: proc(c: ^Console, codepoint: uint) -> Index {
	return _layout_codepoint_to_index(c._font.layout, codepoint)
}

console_char_to_index :: proc(c: ^Console, char: Rune) -> Index {
	return _layout_char_to_index(c._font.layout, char)
}

console_index_to_char :: proc(c: ^Console, index: Index) -> Rune {
	return _layout_index_to_char(c._font.layout, index)
}



create_font_layout :: proc {
	// create_font_layout_chars,
	create_font_layout_codes
}

// create_font_layout_chars :: proc(name: string, cols, rows: int, glyphs: string) {
// 	// TODO
// }

create_font_layout_codes :: proc(name: string, cols, rows: $T, codepoints: []uint)
			where intrinsics.type_is_integer(T) {
	indices_by_codepoints := make(map[uint]Index)
	indices_by_char := make(map[Rune]Index)
	chars_by_index := make(map[Index]Rune)

	for i in 0..<len(codepoints) {
		g := codepoints[i]
		indices_by_codepoints[g] = Index(i)
		indices_by_char[Rune(g)] = Index(i)
		chars_by_index[Index(i)]   = Rune(g)
	}

	layout := new(FontLayout)
	layout.name = name
	layout.cols = cols
	layout.rows = rows
	layout.indices_by_char = indices_by_char
	layout.indices_by_codepoints = indices_by_codepoints
	layout.chars_by_index = chars_by_index

	internal.font_layouts[name] = layout
}


destroy_font_layout :: proc(layout: ^FontLayout) {
	delete(layout.indices_by_char)
	delete(layout.indices_by_codepoints)
	delete(layout.chars_by_index)

	delete_key(&internal.font_layouts, layout.name)
	free(layout)
}


@private _free_all_font_layouts :: proc() {
	for _, &layout in internal.font_layouts {
		destroy_font_layout(layout)
	}
	delete(internal.font_layouts)
}


@private _get_font_layout :: proc(name: string, loc := #caller_location) -> ^FontLayout {
	if name not_in internal.font_layouts do fmt.panicf("invalid font layout '%s'", name, loc=loc)
	return internal.font_layouts[name]
}


@private _init_default_font_layouts :: proc() {
	// NIY
	// _cp437_str := " ☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼ !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~⌂ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■□"
	// create_font_layout_chars("cp437", 16, 16, _cp437_str)

	_cp437_codepoints: []uint = {
	    0x00, 0x263a, 0x263b, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022, 0x25d8, 0x25cb, 0x25d9, 0x2642, 0x2640, 0x266a, 0x266b, 0x263c,
	    0x25ba, 0x25c4, 0x2195, 0x203c, 0xb6, 0xa7, 0x25ac, 0x21a8, 0x2191, 0x2193, 0x2192, 0x2190, 0x221f, 0x2194, 0x25b2, 0x25bc,
	    0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f,
	    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f,
	    0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f,
	    0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f,
	    0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f,
	    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x2302,
	    0xc7, 0xfc, 0xe9, 0xe2, 0xe4, 0xe0, 0xe5, 0xe7, 0xea, 0xeb, 0xe8, 0xef, 0xee, 0xec, 0xc4, 0xc5,
	    0xc9, 0xe6, 0xc6, 0xf4, 0xf6, 0xf2, 0xfb, 0xf9, 0xff, 0xd6, 0xdc, 0xa2, 0xa3, 0xa5, 0x20a7, 0x0192,
	    0xe1, 0xed, 0xf3, 0xfa, 0xf1, 0xd1, 0xaa, 0xba, 0xbf, 0x2310, 0xac, 0xbd, 0xbc, 0xa1, 0xab, 0xbb,
	    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, 0x2555, 0x2563, 0x2551, 0x2557, 0x255d, 0x255c, 0x255b, 0x2510,
	    0x2514, 0x2534, 0x252c, 0x251c, 0x2500, 0x253c, 0x255e, 0x255f, 0x255a, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256c, 0x2567,
	    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256b, 0x256a, 0x2518, 0x250c, 0x2588, 0x2584, 0x258c, 0x2590, 0x2580,
	    0x03b1, 0xdf, 0x0393, 0x03c0, 0x03a3, 0x03c3, 0xb5, 0x03c4, 0x03a6, 0x0398, 0x03a9, 0x03b4, 0x221e, 0x03c6, 0x03b5, 0x2229,
	    0x2261, 0xb1, 0x2265, 0x2264, 0x2320, 0x2321, 0xf7, 0x2248, 0xb0, 0x2219, 0xb7, 0x221a, 0x207f, 0xb2, 0x25a0, 0x25a1,
	}

	_tcod_codepoints: []uint = {
	    0x0020, 0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027, 0x0028, 0x0029, 0x002a, 0x002b, 0x002c, 0x002d, 0x002e, 0x002f,
	    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, 0x0038, 0x0039, 0x003a, 0x003b, 0x003c, 0x003d, 0x003e, 0x003f,
	    0x0040, 0x005b, 0x005c, 0x005d, 0x005e, 0x005f, 0x0060, 0x007b, 0x007c, 0x007d, 0x007e, 0x2591, 0x2592, 0x2593, 0x2502, 0x2500,
	    0x253c, 0x2524, 0x2534, 0x251c, 0x252c, 0x2514, 0x250c, 0x2510, 0x2518, 0x2598, 0x259d, 0x2580, 0x2596, 0x259a, 0x2590, 0x2597,
	    0x2191, 0x2193, 0x2190, 0x2192, 0x25b2, 0x25bc, 0x25c4, 0x25ba, 0x2195, 0x2194, 0x2610, 0x2611, 0x25cb, 0x25c9, 0x2551, 0x2550,
	    0x256c, 0x2563, 0x2569, 0x2560, 0x2566, 0x255a, 0x2554, 0x2557, 0x255d, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, 0x0048, 0x0049, 0x004a, 0x004b, 0x004c, 0x004d, 0x004e, 0x004f, 0x0050,
	    0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, 0x0058, 0x0059, 0x005a, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	    0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067, 0x0068, 0x0069, 0x006a, 0x006b, 0x006c, 0x006d, 0x006e, 0x006f, 0x0070,
	    0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077, 0x0078, 0x0079, 0x007a, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
	}

	create_font_layout_codes(CP437, 16, 16, _cp437_codepoints)
	create_font_layout_codes(TCOD, 32, 8, _tcod_codepoints)
}


@private _layout_codepoint_to_index :: proc {
	_codepoint_to_index_from_layout,
	_codepoint_to_index_from_name,
	_codepoint_to_index_from_default,
}

@private _codepoint_to_index_from_layout :: proc(layout: ^FontLayout, codepoint: uint) -> Index {
	return layout.indices_by_codepoints[codepoint]
}

@private _codepoint_to_index_from_name :: proc(name: string, codepoint: uint) -> Index {
	return _codepoint_to_index_from_layout(internal.font_layouts[name], codepoint)
}

@private _codepoint_to_index_from_default :: proc(codepoint: uint) -> Index {
	return _codepoint_to_index_from_layout(
		internal.default_font_layout, codepoint)
}


@private _layout_char_to_index :: proc {
	_char_to_index_from_layout,
	_char_to_index_from_name,
	_char_to_index_from_default,
}

@private _char_to_index_from_layout :: proc(layout: ^FontLayout, char: Rune) -> Index {
	return layout.indices_by_char[char]
}

@private _char_to_index_from_name :: proc(name: string, char: Rune) -> Index {
	return _char_to_index_from_layout(internal.font_layouts[name], char)
}

@private _char_to_index_from_default :: proc(char: Rune) -> Index {
	return _char_to_index_from_layout(
		internal.default_font_layout, char)
}


@private _layout_index_to_char :: proc {
	_index_to_char_from_layout,
	_index_to_char_from_name,
	_index_to_char_from_default,
}

@private _index_to_char_from_layout :: proc(layout: ^FontLayout, index: Index) -> Rune {
	return layout.chars_by_index[index]
}

@private _index_to_char_from_name :: proc(name: string, index: Index) -> Rune {
	return _index_to_char_from_layout(internal.font_layouts[name], index)
}

@private _index_to_char_from_default :: proc(index: Index) -> Rune {
	return _index_to_char_from_layout(
		internal.default_font_layout, index)
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
camera_to_screen :: proc {
	camera_to_screen_xy,
	camera_to_screen_vec,
}

camera_to_screen_xy :: proc(cam: ^Camera, #any_int x, y: int) -> Vec2 {
	return camera_to_screen_vec(cam, {x, y})
}

camera_to_screen_vec :: proc(cam: ^Camera, pos: Vec2) -> Vec2 {
	return Vec2{
		pos.x - cam._pos.x + cam._viewport.x,
		pos.y - cam._pos.y + cam._viewport.y
	}
}

// Convert world-space 'x' to screen-space 'x'
camera_to_screen_x :: proc(cam: ^Camera, mx: int) -> int {
	return mx - cam._pos.x + cam._viewport.x
}

// Convert world-space 'y' to screen-space 'y'
camera_to_screen_y :: proc(cam: ^Camera, my: int) -> int {
	return my - cam._pos.y + cam._viewport.y
}


// Convert screen-space coordinates to world-space coordinates
camera_to_world :: proc {
	camera_to_world_xy,
	camera_to_world_vec,
}

camera_to_world_xy :: proc(cam: ^Camera, #any_int x, y: int) -> Vec2 {
	return camera_to_world_vec(cam, {x, y})
}

camera_to_world_vec :: proc(cam: ^Camera, pos: Vec2) -> Vec2 {
	return Vec2{
		cam._pos.x - cam._viewport.x + pos.x,
		cam._pos.y - cam._viewport.y + pos.y
	}
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
	internal.exit_value = 1
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







