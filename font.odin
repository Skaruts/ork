package ork

import "core:fmt"
import "base:intrinsics"

import rl "vendor:raylib"
import "utils"


// A bitmap font or tileset
Font :: struct {
	name       : string,
	cols, rows : int,         // width/height of the font in columns/rows
	tw, th     : int,         // tile width / height
	texture    : rl.Texture,
	layout     : string,
	image      : rl.Image,
}


// Deletes the given `font` and frees its memory.
delete_font :: proc(font: ^Font, loc := #caller_location) {
	if font == nil do return
	idx, ok := _get_item_index(internal.fonts[:], font)
	if ok do unordered_remove(&internal.fonts, idx)
	rl.UnloadTexture(font.texture)
	free(font)
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
	return new_font_with_name("", file_path, layout_name)
}

// Creates a named new font from a bitmap font file, optionally with a
// `layout_name`.
new_font_with_name :: proc(name: string, file_path: string,
                          layout_name:=internal.default_font_layout_name
                    ) -> ^Font {
	img := _load_font_image(file_path)
	return new_font_from_image(name, img, layout_name)
}

// Creates a new font from an `Image` object.
new_font_from_image :: proc(name: string, img: rl.Image,
                            layout_name:=internal.default_font_layout_name
                           ) -> ^Font {

	if img.data == nil {
		__warning("font image couldn't be loaded - using default font")
		return internal.default_font
	}

	tex := rl.LoadTextureFromImage(img)
	layout := _get_font_layout(layout_name)

	cols := 16  // TODO: allow other font formats
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

	append(&internal.fonts, font)
	return font
}

@private _load_font_image :: proc(file_path: string) -> rl.Image {
	img := rl.LoadImage( utils.to_cstr(file_path) )

	if img.data != nil {
		if img.format != .UNCOMPRESSED_R8G8B8A8 {
			rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
		}

		// make img transparent around the glyphs, if needed.
		col := rl.GetImageColor(img, 0, 0) // this should be called 'ImageGetPixel', but ok...
		if col != rl.BLANK do rl.ImageColorReplace(&img, col, {0,0,0,0})
	}

	return img
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


