#+feature dynamic-literals
package ork_ui


import "../../utils/stack"
import ork "../../"


Style_Colors :: struct {
	fg, bg : Color,
}

Theme :: struct {
	glyphs  : map[Glyph_Type]Index,
	colors : map[Style_Type]Style_Colors,
}


// NOTE: seems I can't use enums for this, as I want the theme
// to be extensible by users (enumerated arrays are fixed size).

Style_Type :: distinct int
Glyph_Type :: distinct int

Base           :: Style_Type(0)    // style types
Disabled       :: Style_Type(1)
Text           :: Style_Type(2)
Header         :: Style_Type(3)
Separator      :: Style_Type(4)
Number         :: Style_Type(5)
Icon           :: Style_Type(6)
Selection      :: Style_Type(7)
Tooltip        :: Style_Type(8)
Btn_Normal     :: Style_Type(9)
Btn_Hovered    :: Style_Type(10)
Btn_Pressed    :: Style_Type(11)
Toggle_Off     :: Style_Type(12)
Toggle_On      :: Style_Type(13)
Toggle_Hovered :: Style_Type(14)

Style_Count    :: Style_Type(15)
Max_Styles     :: Style_Type(256)


Radio_On           :: Glyph_Type(0)    // glyph types
Radio_Off          :: Glyph_Type(1)
Checkbox_Off       :: Glyph_Type(2)
Checkbox_On        :: Glyph_Type(3)
Checkbox_Full      :: Glyph_Type(4)
Checkbox_L_Bracket :: Glyph_Type(5)
Checkbox_R_Bracket :: Glyph_Type(6)
Folded             :: Glyph_Type(7)
Unfolded           :: Glyph_Type(8)
Line_V             :: Glyph_Type(9)
Line_H             :: Glyph_Type(10)
Cap_Left           :: Glyph_Type(11)
Cap_Right          :: Glyph_Type(12)
Cap_Top            :: Glyph_Type(13)
Cap_Bottom         :: Glyph_Type(14)
Top_left           :: Glyph_Type(15)
Top_Right          :: Glyph_Type(16)
Bottom_Left        :: Glyph_Type(17)
Bottom_Right       :: Glyph_Type(18)
Spinner_Left       :: Glyph_Type(19)
Spinner_Right      :: Glyph_Type(20)

Icon_Count         :: Glyph_Type(21)
Max_Icons          :: Glyph_Type(256)


Style_Data :: struct {
	type   : Style_Type,
	colors : Style_Colors,
}

Glyph_Data :: struct {
	type : Glyph_Type,
	index : Index,
}


@private _glyph_stack  : stack.Stack(Glyph_Data)
@private _style_stack : stack.Stack(Style_Data)


push_glyph :: proc(glyphs: []Glyph_Data) {
	for info in glyphs {
		stack.push_top(&_glyph_stack, Glyph_Data {
			info.type,
			theme.glyphs[info.type],
		})
		theme.glyphs[info.type] = info.index
	}
}

pop_glyph :: proc(count: uint = 1) {
	count := count
	for count > 0 {
		info := stack.pop_top(&_glyph_stack)
		theme.glyphs[info.type] = info.index
		count -= 1
	}
}


push_style :: proc(styles: []Style_Data) {
	for info in styles {
		stack.push_top(&_style_stack, Style_Data {
			info.type,
			theme.colors[info.type],
		})
		theme.colors[info.type] = info.colors
	}
}

pop_style :: proc(count: uint = 1) {
	count := count
	for count > 0 {
		info := stack.pop_top(&_style_stack)
		theme.colors[info.type] = info.colors
		count -= 1
	}
}


new_theme :: proc(th: Theme = {}) -> Theme {
	new_theme := Theme{}
	new_theme.glyphs = make(map[Glyph_Type]Index, Max_Icons, allocator)
	new_theme.colors = make(map[Style_Type]Style_Colors, Max_Styles, allocator)

	if th.glyphs != nil {
		for key, val in th.glyphs {
			new_theme.glyphs[key] = val
		}
		for key, val in th.colors {
			new_theme.colors[key] = val
		}
	}
	return new_theme
}


@private _init_default_theme :: proc() {
	_def_theme = new_theme()

	glyphs  := &_def_theme.glyphs
	colors := &_def_theme.colors

	glyphs[Radio_On]           = 254
	glyphs[Radio_Off]          = 255
	glyphs[Checkbox_Off]       = 0
	glyphs[Checkbox_On]        = 255
	glyphs[Checkbox_Full]      = 254
	glyphs[Checkbox_L_Bracket] = ork.char_to_index(_console, '[')
	glyphs[Checkbox_R_Bracket] = ork.char_to_index(_console, ']')
	glyphs[Unfolded]           = 31
	glyphs[Folded]             = 16
	glyphs[Line_H]             = 196
	glyphs[Line_V]             = 179
	glyphs[Cap_Left]           = 180
	glyphs[Cap_Right]          = 195
	glyphs[Cap_Top]            = 193
	glyphs[Cap_Bottom]         = 194
	glyphs[Top_left]           = 218
	glyphs[Top_Right]          = 191
	glyphs[Bottom_Left]        = 192
	glyphs[Bottom_Right]       = 217
	glyphs[Spinner_Left]       = ork.char_to_index(_console, '<')
	glyphs[Spinner_Right]      = ork.char_to_index(_console, '>')

	colors[Base]           = { ork.GRAY4,   ork.color_darkened(ork.BROWN1, 0.5) }
	colors[Disabled]       = { ork.GREY3,   ork.GRAY1 }
	colors[Text]           = { ork.GREY6,   ork.TRANSP }
	colors[Header]         = { {140, 102, 255, 255}, ork.TRANSP }
	colors[Separator]      = { ork.GRAY3,   ork.TRANSP }
	colors[Number]         = { ork.PURPLE6, ork.TRANSP }
	colors[Icon]           = { ork.ORANGE5, ork.TRANSP }
	colors[Selection]      = { ork.BROWN3,  ork.TRANSP }
	colors[Tooltip]        = { ork.BLACK,   {204, 170, 128, 255} }
	colors[Btn_Normal]     = { ork.BLUE6,   ork.GREY1 }
	colors[Btn_Hovered]    = { ork.BLUE6,   ork.GREY2 }
	colors[Btn_Pressed]    = { ork.BLUE8,   ork.GREY3 }
	colors[Toggle_Off]     = { ork.GRAY4,   ork.BLACK }
	colors[Toggle_On]      = { ork.AMBER5,  ork.DGREY1 }
	colors[Toggle_Hovered] = { ork.AMBER3,  ork.GREY1 }

}


