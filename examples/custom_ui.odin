package examples


import ork "../"  // Ork itself
import "../libs/ui"


UI_HEADER_COL         :: ork.GREEN4
UI_TEXT_SELECTED_COL  :: ork.AMBER5
UI_TEXT_HOTKEYS    :: ork.GRAY2

// Anything Ork UI doesn't support can be created using its API

List_Normal  :: ui.Style_Count + 1
List_Hovered :: ui.Style_Count + 2
List_Pressed :: ui.Style_Count + 3

init_custom_ui :: proc() {
	// set some custom ui colors
	ui.theme.colors[List_Normal]  = { ork.GRAY5, ork.GREY1 }
	ui.theme.colors[List_Hovered] = { ork.GRAY6, ork.GREY3 }
	ui.theme.colors[List_Pressed] = { ork.GRAY8, ork.BLUE4 }
}


ui_list :: proc(pos: ork.Vec2, w, selected: int, items: []string, active: bool) {
	if !active do ui.push_state(.Disabled)

	for text, i in items {
		ui_list_item({pos.x, pos.y+i}, text, i == selected)
	}

	if !active do ui.pop_state()
}

ui_list_item :: proc(pos: ork.Vec2, text: string, selected: bool) {
	item := ui.begin_item(text, {pos.x, pos.y, 0, 0}, {.Expand_X, .Align_Center_X})

	x, y, w, h := ui.unpack_rect(item.rect)
	tx, ty := ui.get_text_position(item)
	fg, bg: ork.Color
	colors := ui.theme.colors
	if ui.is_enabled() {
		fg = selected ? colors[List_Pressed].fg : colors[List_Normal].fg
		bg = selected ? colors[List_Pressed].bg : colors[List_Normal].bg
	} else {
		fg = colors[ui.Disabled].fg
		bg = selected ? ork.BLUE1 : colors[ui.Disabled].bg
	}

	ui.push_line(x, y, w, y, nil, nil, bg)
	ui.push_text(tx, ty, item.text, fg)

	ui.end_item()
}

// TODO: this is a terrible name
ui_selector :: proc(pos: ork.Vec2, selected_idx: int, options: []string) {
	for opt_name, i in options {
		ui_selector_item({pos.x, pos.y+i}, opt_name, i == selected_idx)
	}
}


ui_selector_item :: proc(pos: ork.Vec2, text: string, selected: bool) {
	item := ui.begin_item(text, {pos.x, pos.y, 0, 0}, {})

	x, y, w, h := ui.unpack_rect(item.rect)
	fg := selected ? UI_TEXT_SELECTED_COL : ui.theme.colors[ui.Disabled].fg

	if selected {
		ui.push_cell(x, y, ork.Index(16), UI_TEXT_SELECTED_COL, ork.BLACK)
	}

	ui.push_text(x+2, y, item.text, fg, ork.BLACK)
	ui.end_item()
}

