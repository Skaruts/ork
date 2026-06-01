#+feature dynamic-literals
package ork_ui


import "core:hash"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:strings"

import "../../utils/stack"
import ork "../../"


@private Console :: ork.Console
@private Font    :: ork.Font
@private Color   :: ork.Color
@private Vec2    :: ork.Vec2
@private Rect    :: ork.Rect
@private Rune    :: ork.Rune
@private Index   :: ork.Index


Flags :: bit_set[Item_Flag]
Item_Flag :: enum {
	No_Background, // decorations (for containers)
	No_Border,
	No_Header,

	Align_Left,    // text alignment
	Align_Right,
	Align_Center_X,
	Align_Center_Y,
	Align_Top,
	Align_Bottom,

	Size_X,        // sizing options
	Size_Y,
	Expand_X,      // Expand to parent's size
	Expand_Y,      // (no actual support for layouts yet)
}


State :: enum {
	Enabled,
	Locked,
	Disabled,
}

ID :: distinct u32

Item :: struct {
	id            : ID,
	id_str        : string,

	using rect    : Rect,  // global coords
	local_rect    : Rect,  // local coords
	text          : string,
	tooltip       : string,
	flags         : Flags,

	hovered       : bool,
	pressed       : bool,
	down          : bool,
	released      : bool,
	repeat        : bool,
	value_changed : bool,

	_children     : [dynamic]^Item,
	_parent       : ^Item,
}

@private _console           : ^Console
@private _arena             : virtual.Arena
allocator                   : mem.Allocator

@private _mouse             : Vec2
@private _def_theme         : Theme

@private _items             : stack.Stack(^Item)
@private _id_stack          : stack.Stack(string)
@private _item_cache        : map[ID]^Item
@private _clipping_bounds   : stack.Stack(Rect)
@private _state_stack       : stack.Stack(State)

@private _prev_item         : ^Item
@private _item_hovered      : ^Item
@private _item_pressed      : ^Item
@private _item_last_pressed : ^Item
@private _item_last_hovered : ^Item


theme     : Theme
has_mouse : bool



init :: proc(c: ^Console) {
	allocator = virtual.arena_allocator(&_arena)
	_console = c

	_init_default_theme()
	theme = new_theme(_def_theme)  // TODO: confirm that this doesn't use the same memory

	_item_cache = make(map[ID]^Item,    allocator)
	stack.init(&_items,           allocator)
	stack.init(&_render_stack,    allocator)
	stack.init(&_clipping_bounds, allocator)
	stack.init(&_glyph_stack,     allocator)
	stack.init(&_style_stack,     allocator)
	stack.init(&_id_stack,        allocator)
	stack.init(&_state_stack,     allocator)
}


close :: proc() {
	free_all(allocator)
	virtual.arena_destroy(&_arena)
}


begin_frame :: proc() {
	_mouse = ork.get_mouse_position(_console)
}


end_frame :: proc() {
	assert(stack.length(&_items) == 0)
	assert(stack.length(&_id_stack) == 0)
	assert(stack.length(&_glyph_stack) == 0)
	assert(stack.length(&_style_stack) == 0)
	assert(stack.length(&_clipping_bounds) == 0)
	assert(stack.length(&_state_stack) == 0)

	ork.clear_cells(_console)
	{
		for step in _render_stack._items {
			_do_render_step(step)
		}
		stack.empty(&_render_stack)
	}
	ork.render(_console)


	has_mouse = _item_hovered != nil || _item_pressed != nil \
	         || _item_last_hovered != nil || _item_last_pressed != nil \
	         // || _curr_popup != nil

	if _item_hovered == nil {
		_item_last_hovered = nil
		// _item_last_hovered_with_info = nil
	}
	if _item_pressed == nil do _item_last_pressed = nil

	_item_hovered = nil
	_item_pressed = nil
}




/*******************************************************************************

		UI State

*******************************************************************************/
is_disabled :: proc() -> bool {
	return stack.length(&_state_stack) != 0 \
	    && stack.peek_top(&_state_stack) == .Disabled
}

is_enabled :: proc() -> bool {
	return stack.length(&_state_stack) == 0 \
	|| stack.peek_top(&_state_stack) == .Enabled
}

push_state :: proc(st: State) {
	stack.push_top(&_state_stack, st)
}

pop_state :: proc(count: int = 1, loc := #caller_location) {
	for i in 0 ..< count {
		stack.pop_top(&_state_stack, loc=loc)
	}
}


/*******************************************************************************

		Render stack.Stack API

*******************************************************************************/
@private Render_Step_Cell :: struct {
	x, y  : int,
	glyph : Maybe(Index),
	fg    : Maybe(Color),
	bg    : Maybe(Color),
}

@private Render_Step_Text :: struct {
	x, y  : int,
	text : string,
	fg    : Maybe(Color),
	bg    : Maybe(Color),
}

@private Render_Step_Line :: struct {
	x1, y1, x2, y2 : int,
	glyph   : Maybe(Index),
	fg      : Maybe(Color),
	bg      : Maybe(Color),
}

@private Render_Step_Rect :: struct {
	filled     : bool,
	x, y, w, h : int,
	glyph      : Maybe(Index),
	fg         : Maybe(Color),
	bg         : Maybe(Color),
}

@private Render_Step_Circle :: struct {
	filled  : bool,
	x, y, r : int,
	glyph   : Maybe(Index),
	fg      : Maybe(Color),
	bg      : Maybe(Color),
}

@private Render_Step_Code :: struct {
	code : proc(),
}

@private Render_Step_Clip :: struct {
	rect: Maybe(Rect),
}

@private RenderStep :: union {
	Render_Step_Cell,
	Render_Step_Text,
	Render_Step_Line,
	Render_Step_Rect,
	Render_Step_Circle,
	Render_Step_Code,
	Render_Step_Clip,
}

@private _render_stack : stack.Stack(RenderStep)

push_cell :: proc(x, y: int, glyph: Maybe(Index) = nil,
                   fg: Maybe(Color) = nil, bg: Maybe(Color) = nil) {
	stack.push_top(&_render_stack, Render_Step_Cell {x, y, glyph, fg, bg})
}

push_text :: proc(x, y: int, text: string, fg: Maybe(Color) = nil,
                   bg: Maybe(Color) = nil) {
	stack.push_top(&_render_stack, Render_Step_Text {x, y, text, fg, bg})
}

push_line :: proc(x1, y1, x2, y2: int, glyph: Maybe(Index) = nil,
                   fg: Maybe(Color) = nil, bg: Maybe(Color) = nil) {
	stack.push_top(&_render_stack, Render_Step_Line {x1, y1, x2, y2, glyph, fg, bg})
}

push_rect :: proc(filled: bool, x, y, w, h: int, glyph: Maybe(Index) = nil,
                   fg: Maybe(Color) = nil, bg: Maybe(Color) = nil) {
	stack.push_top(&_render_stack, Render_Step_Rect {filled, x, y, w, h, glyph, fg, bg})
}

push_circle :: proc(filled: bool, x, y, r: int, glyph: Maybe(Index) = nil,
                   fg: Maybe(Color) = nil, bg: Maybe(Color) = nil) {
	stack.push_top(&_render_stack, Render_Step_Circle {filled, x, y, r, glyph, fg, bg})
}

run_code :: proc(code: proc()) {
	stack.push_top(&_render_stack, Render_Step_Code {code})
}

push_caps_h :: proc(x, y: int, text: string) {
	length := ork.string_len(text) + 2

	colors := theme.colors
	fg := is_enabled() ? colors[Base].fg : colors[Disabled].fg
	bg := is_enabled() ? colors[Base].bg : colors[Disabled].bg

	push_rect(true, x+1, y, length-2, 1, ' ', nil, bg)
	push_cell(x, y, theme.glyphs[Cap_Left], fg)
	push_cell(x + length-1, y, theme.glyphs[Cap_Right], fg)
}

push_clip :: proc(rect: Rect, relative := false) {
	if !relative {
		_push_clip_impl(rect.x, rect.y, rect.w, rect.h)
	} else {
		item := stack.peek_top(&_items)
		_push_clip_impl(
			item.x + rect.x,
			item.y + rect.y,
			item.w + rect.w,
			item.h + rect.h,
		)
	}
}

@private _push_clip_impl :: proc(x, y, w, h: int) {
	x, y, w, h := x, y, w, h

	if stack.length(&_clipping_bounds) != 0 {
		// TODO: this could be made easier with a 'rect_intersection' proc

		cb := stack.peek_top(&_clipping_bounds)
		cx, cy, cw, ch := unpack_rect(cb)

		x = max(x, cx)
		y = max(y, cy)

		x2,  y2  := x+w,   y+h
		px2, py2 := cx+cw, cy+ch

		if x2 > px2 {
			diff := x2-px2
			w = max(0, w-diff)
		}

		if y2 > py2 {
			diff := y2-py2
			h = max(0, h-diff)
		}
	}

	clip_area := Rect{x, y, w, h}
	stack.push_top(&_clipping_bounds, clip_area)
	stack.push_top(&_render_stack, Render_Step_Clip{clip_area})
}



pop_clip :: proc() {
	stack.pop_top(&_clipping_bounds)

	if stack.length(&_clipping_bounds) != 0 {
		cb := stack.peek_top(&_clipping_bounds)
		stack.push_top(&_render_stack, Render_Step_Clip{cb})
	} else {
		stack.push_top(&_render_stack, Render_Step_Clip{})
	}
}


push_frame :: proc(x, y, w, h: int) {
	x2 := x+w-1
	y2 := y+h-1

	glyphs := theme.glyphs
	colors := theme.colors

	fg := is_enabled() ? colors[Base].fg : colors[Disabled].fg

	push_line(x+1,  y, x2-1,  y, glyphs[Line_H], fg)
	push_line(x+1, y2, x2-1, y2, glyphs[Line_H], fg)
	push_line(x,  y+1,  x, y2-1, glyphs[Line_V], fg)
	push_line(x2, y+1, x2, y2-1, glyphs[Line_V], fg)

	push_cell( x,  y, glyphs[Top_left], fg)
	push_cell(x2,  y, glyphs[Top_Right], fg)
	push_cell( x, y2, glyphs[Bottom_Left], fg)
	push_cell(x2, y2, glyphs[Bottom_Right], fg)
}


@private _do_render_step :: proc(step: RenderStep) {
	switch &s in step {
		case Render_Step_Cell:   ork.draw_cell(_console, s.x, s.y, s.glyph, s.fg, s.bg)
		case Render_Step_Text:   ork.draw_text(_console, s.x, s.y, s.text, s.fg, s.bg)
		case Render_Step_Line:   ork.draw_line(_console, s.x1, s.y1, s.x2, s.y2, s.glyph, s.fg, s.bg)
		case Render_Step_Rect:   ork.draw_rect(_console, s.filled, s.x, s.y, s.w, s.h, s.glyph, s.fg, s.bg)
		case Render_Step_Circle: ork.draw_circle(_console, s.filled, s.x, s.y, s.r, s.glyph, s.fg, s.bg)
		case Render_Step_Code:   s.code()
		case Render_Step_Clip:   ork.set_clipping_area(_console, s.rect)
	}
}




/*******************************************************************************

		Item Private API

*******************************************************************************/

get_text_position :: proc(item: ^Item) -> (int, int) {
	flags := Flags{.Size_X, .Expand_X}

	if flags & item.flags == {} do return item.x, item.y

	tx, ty: int
	length := ork.string_len(item.text)

	if .Align_Left in item.flags {
		// tx = item.x

	} else if .Align_Center_X in item.flags {
		if length < item.w-1 {
			tx = max(0, item.w/2 - length/2)
			if item.w % 2 == 0 do tx -= 1
		}

	} else if .Align_Right in item.flags {
		tx = item.w-length
	}


	if .Align_Top in item.flags {
		// ty = item.y

	} else if .Align_Center_Y in item.flags {
		ty = max(0, item.h/2 )
		if item.h % 2 == 0 do ty -= 1

	} else if .Align_Bottom in item.flags {
		ty = max(0, item.h-1)
	}

	tx += item.rect.x
	ty += item.rect.y

	return tx, ty
}



@private _adjust_size :: proc(text: string, rect: Rect, flags: Flags) -> (string, Rect) {
	parent: ^Item
	if stack.length(&_items) > 0 {
		parent = stack.peek_top(&_items)
	}

	text := text
	rect := rect

	if .Size_X in flags {
		max_len := rect.w-3
		length := ork.string_len(text)

		if max_len > 0 && length >= rect.w {
			if rect.w > 3 && abs(length-max_len) >= 3 {
				text = fmt.tprintf("%s%s", text[ : max_len-1 ], "..")
			} else {
				text = text[ : max_len-1 ]
			}
		}

	} else if .Expand_X in flags && parent != nil{
		// expand to parent size
		rect.w = parent.w
		rect.x = 0
		if .No_Border not_in parent.flags {
			rect.x = 1
			rect.w -= 2
		}

	} else {
		// use text size, or else 1
		rect.w = max(1, ork.string_len(text))
	}


	if .Size_Y in flags {
		// do nothing

	} else if .Expand_Y in flags && parent != nil {
		// expand to parent size
		rect.h = parent.h
		rect.y = 0
		if .No_Border not_in parent.flags {
			rect.y = 1
			rect.h -= 2
		}

	} else {
		rect.h = max(1, rect.h)
	}

	return text, rect

}


ID_PREFIX  :: "$!"
ID_TOK     :: ID_PREFIX + ">>"
ID_TOK_ALL :: ID_PREFIX + "<<"

@private _parse_id_text :: proc(input_str: string) -> (string, string) {
	id_str, text, token, left, right : string
	start, end : int

	if input_str == "" do return "", ""

	if !strings.contains(input_str, ID_TOK)     \
	&& !strings.contains(input_str, ID_TOK_ALL) {
		id_str   = input_str
		text = input_str
	} else {
		start = strings.index(input_str, ID_PREFIX)
		end   = start + len(ID_TOK)

		token = input_str[start : end]
		text = input_str[:start]
		id_str = token == ID_TOK     \
		   ? input_str[end : ]   \
		   : input_str
	}

	return id_str, text
}

@private _hash_id :: proc() -> ID {
	if stack.length(&_id_stack) == 0 do return 0
	full_str := strings.concatenate(_id_stack._items[:], context.temp_allocator)
	return ID(hash.crc32(transmute([]u8) full_str))
}



/*******************************************************************************

		Item Public API

*******************************************************************************/

is_under_mouse :: proc(x, y, w, h: int) -> bool {
	return _mouse.x >= x && _mouse.x < x+w \
	    && _mouse.y >= y && _mouse.y < y+h
}




push_id :: proc(id_str: string) {
	stack.push_top(&_id_stack, id_str)
}

pop_id :: proc() {
	stack.pop_top(&_id_stack)
}



begin_item :: proc(text: string, rect: Rect, flags: Flags = {}) -> ^Item {
	item   : ^Item
	id_str : string
	id     : ID

	text := text
	rect := rect

	id_str, text = _parse_id_text(text)
	text, rect = _adjust_size(text, rect, flags == nil ? {} : flags)

	if id_str != "" {
		push_id(id_str)
		id = _hash_id()
	}

	if id_str != "" && id in _item_cache {
		item = _item_cache[id]
		item.released = false
		item.pressed = false
	} else {
		item = new(Item, allocator)

		if id_str != "" {
			item.id = id
			_item_cache[item.id] = item
		}
		item.text = strings.clone(text, allocator)
		item.local_rect = rect
		item.rect = rect

		if stack.length(&_items) != 0 {
			item._parent = stack.peek_top(&_items)
		}
	}
	stack.push_top(&_items, item)

	if item._parent != nil {
		item.x = item._parent.x + item.local_rect.x
		item.y = item._parent.y + item.local_rect.y
	}

	item.id_str = id_str
	if flags != nil do item.flags = flags

	return item
}

// an item can be passed in to check if it matches
end_item :: proc() -> ^Item {
	item := stack.pop_top(&_items)
	if item.hovered {
		_item_last_hovered = item
		// if item.tooltip do _item_last_hovered_with_info = item
	}
	if item.pressed || item.down do _item_last_pressed = item

	_prev_item = item
	if item.id_str != "" {
		pop_id()
	}
	return item
}

// Returns the a position for the next column from the previous item,
// multiplied by count (this is multiplied by the previous widget's width).
next_col :: proc(count: int = 1, loc := #caller_location) -> Vec2 {
	assert(count > 0, "count must be greater than zero", loc=loc)
	if _prev_item == nil do return {}
	return {
		_prev_item.local_rect.x + _prev_item.local_rect.w * count,
		_prev_item.local_rect.y
	}
}

// Returns the a position for the next row below the previous item,
// multiplied by count (this is multiplied by the previous widget's height).
next_row :: proc(count: int = 1, loc := #caller_location) -> Vec2 {
	assert(count > 0, "count must be greater than zero", loc=loc)
	if _prev_item == nil do return {}
	return {
		0,
		_prev_item.local_rect.y + _prev_item.local_rect.h * count
	}
}


next_x :: proc(count: int = 1, loc := #caller_location) -> int {
	return _prev_item.local_rect.x + _prev_item.local_rect.w * count
}

next_y :: proc(count: int = 1, loc := #caller_location) -> int {
	return _prev_item.local_rect.y + _prev_item.local_rect.h * count
}




unpack_rect :: #force_inline proc(rect: Rect) -> (int, int, int, int) {
	return rect.x, rect.y, rect.w, rect.h
}



item_check_state :: proc {
	item_check_state_i,
	item_check_state_r,
}

item_check_state_i :: proc(item: ^Item) {
	item_check_state_r(item, item.x, item.y, item.w, item.h)
}

item_check_state_r :: proc(item: ^Item, x, y, w, h: int) {
	item_check_hovered(item, x, y, w, h)
	item_check_pressed(item)
}



item_check_hovered :: proc {
	item_check_hovered_i,
	item_check_hovered_r,
}

item_check_hovered_i :: proc(item: ^Item) {
	item_check_hovered_r(item, item.x, item.y, item.w, item.h)
}

item_check_hovered_r :: proc(item: ^Item, x, y, w, h: int) {
	// local is_popup = ui.popup_ids[item.old_id] ~= nil
	// if is_popup and ui.curr_popup_id ~= item.old_id then return nil end
	// if not is_popup and ui.curr_popup_id ~= nil and not item.is_in_popup then return nil end

	item.hovered = is_enabled() && is_under_mouse(x, y, w, h) \
	           && (_item_last_pressed == nil || _item_last_pressed == item)

	if item.hovered {
		_item_hovered = item

		/*    Tooltip    */
		// if item.info && ui.id_last_hovered_with_info == item.old_id then
		// 	if not ui.info_item then ui.start_timer(1) end
		// 	ui.info_item = item
		// end

	} else {
		/*    Tooltip    */

		// if item.info && ui.id_last_hovered_with_info == item.old_id {
		// 	ui.stop_timer()
		// 	ui.info_item = nil
		// }
	}
}

item_check_pressed :: proc(item: ^Item) {
	if item.hovered && is_enabled() {
		item.pressed  = ork.mouse_pressed({.MouseLeft})  && _item_last_pressed == nil
		item.down     = ork.mouse_down({.MouseLeft})     && _item_last_pressed == item
		item.released = ork.mouse_released({.MouseLeft}) && _item_last_pressed == item
		item.repeat   = item.hovered && ork.mouse_repeat({.MouseLeft})
	} else{
		item.down = ork.mouse_down({.MouseLeft}) && _item_last_pressed == item
	}

	if item.pressed || item.down do _item_pressed = item
}



_combine_default_flags :: proc(flags: Flags, exclude:Flags, default: Flags) -> Flags {
	flags := flags
	if exclude & flags == {} do flags += default
	return flags
}


/*******************************************************************************

		Predefined Widgets

*******************************************************************************/
// Must be called after any proc that creates any kind of container,
// after all the child widgets have been processed.
end_container :: proc() {
	end_item()
}

// A panel with a background color and a frame. Similar to a window in other UIs.
container :: proc(title: string, rect: Rect, flags: Flags = {}) -> ^Item {
	flags := flags + {.Size_X, .Size_Y}

	item := begin_item(title, rect, flags)
	if item != nil {
		x, y, w, h := unpack_rect(item.rect)

		colors := theme.colors
		fg := is_enabled() ? colors[Base].fg : colors[Disabled].fg
		bg := is_enabled() ? colors[Base].bg : colors[Disabled].bg
		header_fg := is_enabled() ? colors[Header].fg : fg

		if .No_Background not_in item.flags {
			push_rect(true, x, y, w ,h, nil, nil, bg)
		}

		if .No_Border not_in item.flags {
			push_frame(x, y, w, h)
		}

		if .No_Header not_in item.flags \
		&& item.text != "" {
			hx := x+1
			push_caps_h(hx, y, item.text)
			push_text(hx+1, y, item.text, header_fg)
		}
	}
	return item
}


// Makes a regular button. By default, unless overriden with flags, if no
// `size` is given, the width is inferred from text length, and height
// defaults to 1.
button :: proc(pos: Vec2, text: string, flags: Flags = {}, size: Vec2 = {}) -> ^Item {
	flags := _combine_default_flags(flags, {.Align_Left, .Align_Right}, {.Align_Center_X})
	flags = _combine_default_flags(flags, {.Align_Top, .Align_Bottom}, {.Align_Center_Y})

	item := begin_item(text, {pos.x, pos.y, size.x, size.y}, flags)

	x, y, w, h := unpack_rect(item.rect)
	item_check_state(item)

	style : Style_Type = is_disabled() ? Disabled       \
	                   : item.down     ? Btn_Pressed    \
	                   : item.hovered  ? Btn_Hovered    \
	                   :                 Btn_Normal

	fg, bg := theme.colors[style].fg, theme.colors[style].bg

	if bg.a > 0 do push_rect(true, x, y, w, h, nil, nil, bg)

	tx, ty := get_text_position(item)
	if fg.a > 0 do push_text(tx, ty, text, fg)

	return end_item()
}


// Makes an icon button. The width and height are always {1, 1}
icon_button :: proc(pos: Vec2, glyph: Index, flags: Flags = {}) -> ^Item {
	flags := flags + {.Size_X, .Size_Y}
	flags -= {.Expand_X, .Expand_Y}

	text := fmt.tprintf("%r", ork.index_to_char(_console, glyph))
	return button(pos, text, flags, {1, 1})
}


// Displays simple text. If you need more options, use the `label`.
text :: proc(pos: Vec2, text: string, fg: Maybe(Color)=nil) -> ^Item {
	item := begin_item(text, {pos.x, pos.y, 0, 0}, {})
	if item != nil {
		_fg, ok := fg.?
		colors := theme.colors
		fg :=  is_enabled() ? (ok ? _fg : colors[Text].fg) : colors[Disabled].fg
		push_text(item.x, item.y, text, fg)
	}
	return end_item()
}


// Shortcut for displaying simple text from numbers with a `Digit` color
number :: proc {
	number_int,
	number_float,
}

// TODO: option for padding
number_int :: proc(pos: Vec2, #any_int num: int) -> ^Item {
	return text(pos, fmt.tprintf("%d", num), theme.colors[Number].fg)
}

number_float :: proc(pos: Vec2, num: string, precision: int) -> ^Item {
	format := "%%.%df"
	format = fmt.tprintf(format, precision)
	return text(pos, fmt.tprintf(format, num), theme.colors[Number].fg)

}


_get_label_colors :: proc(item: ^Item) -> (Color, Color) {
	colors := theme.colors
	style : Style_Type = is_enabled() ? Text : Disabled
	return colors[style].fg, colors[style].bg
}

label :: proc(pos: Vec2, text: string, flags: Flags = {}, size: Vec2 = {}) -> ^Item {
	flags := _combine_default_flags(flags, {.Align_Center_X, .Align_Right}, {.Align_Left})
	flags = _combine_default_flags(flags, {.Align_Center_Y, .Align_Bottom}, {.Align_Top})

	item := begin_item(text, {pos.x, pos.y, size.x, size.y}, flags)
	if item != nil {
		x, y, w, h := unpack_rect(item.rect)
		fg, bg := _get_label_colors(item)
		if bg.a > 0 do push_rect(true, x, y, w, h, nil, nil, bg)

		tx, ty := get_text_position(item)
		if fg.a > 0 do push_text(tx, ty, text, fg)
	}
	return end_item()
}


separator_v :: proc(pos: Vec2, #any_int length: int, color: Maybe(Color) = nil) -> ^Item {
	item := begin_item("", {pos.x, pos.y, 1, length}, {})
	if item != nil {
		c, ok := color.?
		color :=  ok ? c : (is_enabled() ? theme.colors[Separator].fg : theme.colors[Disabled].fg)
		if color.a > 0 {
			push_line(item.x, item.y, item.x, item.y+length, theme.glyphs[Line_V], color)
		}
	}
	return end_item()
}

separator_h :: proc(pos: Vec2, #any_int length: int, color: Maybe(Color) = nil) -> ^Item {
	item := begin_item("", {pos.x, pos.y, length, 1}, {})
	if item != nil {
		c, ok := color.?
		color :=  ok ? c : (is_enabled() ? theme.colors[Separator].fg : theme.colors[Disabled].fg)
		if color.a > 0 {
			push_line(item.x, item.y, item.x+length, item.y, theme.glyphs[Line_H], color)
		}
	}
	return end_item()
}


// Makes a button that is toggleable. If the width or height are zero, the width is
// inferred from text length, and height defaults to 1.
toggle_button :: proc(pos: Vec2, text: string, enabled: ^bool,
                        flags: Flags = {}, size: Vec2 = {}) -> ^Item {
	flags := _combine_default_flags(flags, {.Align_Left, .Align_Right}, {.Align_Center_X})
	flags = _combine_default_flags(flags, {.Align_Top, .Align_Bottom}, {.Align_Center_Y})

	colors := theme.colors
	glyphs := theme.glyphs

	item := begin_item(text, {pos.x, pos.y, size.x, size.y}, flags)
	x, y, w, h := unpack_rect(item.rect)
	item_check_state(item)

	old_val := enabled^
	if item.pressed do enabled^ = !enabled^
	item.value_changed = old_val != enabled^

	bg, fg : Color
	if is_enabled() {
		bg = item.hovered ? colors[Toggle_Hovered].bg : (enabled^ ? colors[Toggle_On].bg : colors[Toggle_Off].bg)
		fg = enabled^ ? colors[Toggle_On].fg : colors[Toggle_Off].fg
	} else {
		bg = colors[Toggle_Off].bg.a > 0 ? colors[Disabled].bg : ork.TRANSP
		fg = colors[Disabled].fg
	}

	if bg.a > 0 do push_rect(true, x, y, w, h, nil, nil, bg)

	push_text(x, y, text, fg)

	return end_item()

}


radio :: proc(pos: Vec2, text: string, selected: bool,
                flags: Flags = {}, size: Vec2 = {}) -> ^Item {
	text := fmt.tprintf("  %s", text)

	item := begin_item(text, {pos.x, pos.y, size.x, size.y}, flags)
	selected := selected

	x, y, w, h := unpack_rect(item.rect)
	item_check_state(item)

	if item.pressed do selected = !selected
	glyph := selected ? theme.glyphs[Radio_On] : theme.glyphs[Radio_Off]

	bg, fg, fg_text : Color
	colors := theme.colors
	if is_enabled() {
		bg = item.hovered ? colors[Toggle_Hovered].bg : colors[Toggle_Off].bg // \\(selected ? colors[Toggle_On].bg : colors[Toggle_Off].bg)
		fg = selected ? colors[Toggle_On].fg : colors[Toggle_Off].fg
		fg_text = colors[Text].fg
	} else {
		bg = colors[Toggle_Off].bg.a > 0 ? colors[Disabled].bg : ork.TRANSP
		fg = colors[Disabled].fg
		fg_text = fg
	}

	push_rect(true, x, y, w, h, nil, nil, bg)
	push_text(x, y, text, fg_text)
	push_cell(x, y, glyph, fg)

	return end_item()
}


checkbox :: proc(pos: Vec2, text: string, enabled: ^bool,
                   flags: Flags = {}, size: Vec2 = {}) -> ^Item {
	colors := theme.colors
	glyphs := theme.glyphs

	text := fmt.tprintf("    %s", text)
	item := begin_item(text, {pos.x, pos.y, size.x, size.y}, flags)

	x, y, w, h := unpack_rect(item.rect)
	item_check_state(item)

	old_val := enabled^
	if item.pressed do enabled^ = !enabled^
	item.value_changed = old_val != enabled^

	glyph := enabled^ ? glyphs[Radio_On] : 0

	bg, fg : Color
	if is_enabled() {
		bg = item.hovered ? colors[Toggle_Hovered].bg : ork.TRANSP // \\(enabled ? colors[Toggle_On].bg : colors[Toggle_Off].bg)
		fg = colors[Text].fg
	} else {
		bg = ork.TRANSP
		fg = colors[Disabled].fg
	}

	if bg.a > 0 do push_rect(true, x, y, w, h, nil, nil, bg)
	push_text(x, y, text, fg)

	push_rect(true, x, y, 3, h, nil, nil, colors[Toggle_On].bg)
	push_cell(x, y,   glyphs[Checkbox_L_Bracket], fg)
	push_cell(x+1, y, glyph, fg)
	push_cell(x+2, y, glyphs[Checkbox_R_Bracket], fg)

	return end_item()
}


toggle :: proc(pos: Vec2, text: string, enabled: ^bool,
                   flags: Flags = {}, size: Vec2 = {}) -> ^Item {
	colors := theme.colors
	glyphs := theme.glyphs

	text := fmt.tprintf("   %s", text)

	item := begin_item(text, {pos.x, pos.y, size.x, size.y}, flags)

	x, y, w, h := unpack_rect(item.rect)
	item_check_state(item)

	old_val := enabled^
	if item.pressed do enabled^ = !enabled^
	item.value_changed = old_val != enabled^

	glyph := enabled^ ? glyphs[Radio_On] : 0

	bg, fg, fg_text : Color
	if is_enabled() {
		bg = item.hovered ? colors[Toggle_Hovered].bg : ork.TRANSP // \\(enabled ? colors[Toggle_On].bg : colors[Toggle_Off].bg)
		fg = enabled^ ? colors[Toggle_On].fg : colors[Toggle_Off].fg
		fg_text = colors[Text].fg
	} else {
		bg = ork.TRANSP
		fg = colors[Disabled].fg
		fg_text = fg
	}

	if bg.a > 0 do push_rect(true, x, y, w, h, nil, nil, bg)
	push_text(x, y, text, fg_text)

	push_rect(true, x, y, 2, h, nil, nil, colors[Toggle_On].bg)
	if enabled^ {
		push_cell(x,   y, glyphs[Radio_On],  fg)
	} else {
		push_cell(x+1, y, glyphs[Radio_On], colors[Disabled].fg)
	}

	return end_item()
}


spinner :: proc(pos: Vec2, #any_int min_w: int, text: string,
                value: ^int, #any_int lo, hi, step: int,
                flags: Flags = {}/*, size: Vec2 = {}*/
               ) -> ^Item {

	tlen := ork.string_len(text)

	format := "%d"
	num_w := max(min_w, ork.string_len( fmt.tprintf(format, lo < 0 ? lo : hi) ))
	w := tlen + 3 + num_w

	item := begin_item(text, {pos.x, pos.y, w, 1}, flags + {.Size_X})

	sl := ork.index_to_char(_console, theme.glyphs[Spinner_Left])
	sr := ork.index_to_char(_console, theme.glyphs[Spinner_Right])

	old_value := value^
	if button({tlen+1, 0}, fmt.tprintf("%r", sl)).repeat {
		value^ = max(lo, value^ - step)
	}

	if button({tlen+2, 0}, fmt.tprintf("%r", sr)).repeat {
		value^ = min(hi, value^ + step)
	}
	item.value_changed = old_value != value^

	x, y := item.x, item.y
	nx := x + tlen + 3
	push_text(x, y, text, theme.colors[Text].fg)
	push_rect(true, nx, y, num_w, item.h, nil, nil, theme.colors[Toggle_Off].bg)
	digit_text := strings.right_justify(fmt.tprintf(format, value^), num_w, " ", context.temp_allocator)
	push_text(nx, y, digit_text, theme.colors[Number].fg)

	return end_item()
}

spinnerf :: proc(pos: Vec2, min_w: int, text: string, value: ^f32,
                 lo, hi, step: f32, precision := 2, flags: Flags = {}
                ) -> ^Item {

	tlen := ork.string_len(text)

	format := fmt.tprintf("%%.%df", precision)
	num_w := max(min_w, ork.string_len( fmt.tprintf(format, lo < 0 ? lo : hi) ))
	w := tlen + 3 + num_w

	item := begin_item(text, {pos.x, pos.y, w, 1}, flags + {.Size_X})

	sl := ork.index_to_char(_console, theme.glyphs[Spinner_Left])
	sr := ork.index_to_char(_console, theme.glyphs[Spinner_Right])

	old_value := value^
	if button({tlen+1, 0}, fmt.tprintf("%r", sl)).repeat {
		value^ = max(lo, value^ - step)
	}

	if button({tlen+2, 0}, fmt.tprintf("%r", sr)).repeat {
		value^ = min(hi, value^ + step)
	}
	item.value_changed = old_value != value^

	x, y := item.x, item.y
	nx := x + tlen + 3
	push_text(x, y, text, theme.colors[Text].fg)
	push_rect(true, nx, y, num_w, item.h, nil, nil, theme.colors[Toggle_Off].bg)
	digit_text := strings.right_justify(fmt.tprintf(format, value^), num_w, " ", context.temp_allocator)
	push_text(nx, y, digit_text, theme.colors[Number].fg)

	return end_item()
}

