#+feature dynamic-literals
package ork


import "core:time"
import "core:fmt"

import rl "vendor:raylib"


FIRST_REPEAT_COOLDOWN  :: 0.28 // 0.25
SECOND_REPEAT_COOLDOWN :: 0.08 // 0.05


// NOTE: I override all of these just so they conform to this enum style (not full caps)
Keyboard_Key :: enum {
	Null            = 0,              // Key: NULL, used for no key pressed
	// Alphanumeric keys
	Apostrophe      = 39,             // Key: '
	Comma           = 44,             // Key: ,
	Minus           = 45,             // Key: -
	Period          = 46,             // Key: .
	Slash           = 47,             // Key: /
	N0              = 48,             // Key: 0
	N1              = 49,             // Key: 1
	N2              = 50,             // Key: 2
	N3              = 51,             // Key: 3
	N4              = 52,             // Key: 4
	N5              = 53,             // Key: 5
	N6              = 54,             // Key: 6
	N7              = 55,             // Key: 7
	N8              = 56,             // Key: 8
	N9              = 57,             // Key: 9
	Semicolon       = 59,             // Key: ;
	Equal           = 61,             // Key: =
	A               = 65,             // Key: A | a
	B               = 66,             // Key: B | b
	C               = 67,             // Key: C | c
	D               = 68,             // Key: D | d
	E               = 69,             // Key: E | e
	F               = 70,             // Key: F | f
	G               = 71,             // Key: G | g
	H               = 72,             // Key: H | h
	I               = 73,             // Key: I | i
	J               = 74,             // Key: J | j
	K               = 75,             // Key: K | k
	L               = 76,             // Key: L | l
	M               = 77,             // Key: M | m
	N               = 78,             // Key: N | n
	O               = 79,             // Key: O | o
	P               = 80,             // Key: P | p
	Q               = 81,             // Key: Q | q
	R               = 82,             // Key: R | r
	S               = 83,             // Key: S | s
	T               = 84,             // Key: T | t
	U               = 85,             // Key: U | u
	V               = 86,             // Key: V | v
	W               = 87,             // Key: W | w
	X               = 88,             // Key: X | x
	Y               = 89,             // Key: Y | y
	Z               = 90,             // Key: Z | z
	Left_Bracket    = 91,             // Key: [
	Backslash       = 92,             // Key: '\'
	Right_Bracket   = 93,             // Key: ]
	Grave           = 96,             // Key: `
	// Function keys
	Space           = 32,             // Key: Space
	Escape          = 256,            // Key: Esc
	Enter           = 257,            // Key: Enter
	Tab             = 258,            // Key: Tab
	Backspace       = 259,            // Key: Backspace
	Insert          = 260,            // Key: Ins
	Delete          = 261,            // Key: Del
	Right           = 262,            // Key: Cursor right
	Left            = 263,            // Key: Cursor left
	Down            = 264,            // Key: Cursor down
	Up              = 265,            // Key: Cursor up
	Page_Up         = 266,            // Key: Page up
	Page_Down       = 267,            // Key: Page down
	Home            = 268,            // Key: Home
	End             = 269,            // Key: End
	Caps_Lock       = 280,            // Key: Caps lock
	Scroll_Lock     = 281,            // Key: Scroll down
	Num_Lock        = 282,            // Key: Num lock
	Print_Screen    = 283,            // Key: Print screen
	Pause           = 284,            // Key: Pause
	F1              = 290,            // Key: F1
	F2              = 291,            // Key: F2
	F3              = 292,            // Key: F3
	F4              = 293,            // Key: F4
	F5              = 294,            // Key: F5
	F6              = 295,            // Key: F6
	F7              = 296,            // Key: F7
	F8              = 297,            // Key: F8
	F9              = 298,            // Key: F9
	F10             = 299,            // Key: F10
	F11             = 300,            // Key: F11
	F12             = 301,            // Key: F12
	Left_Shift      = 340,            // Key: Shift left
	Left_Control    = 341,            // Key: Control left
	Left_Alt        = 342,            // Key: Alt left
	Left_Super      = 343,            // Key: Super left
	Right_Shift     = 344,            // Key: Shift right
	Right_Control   = 345,            // Key: Control right
	Right_Alt       = 346,            // Key: Alt right
	Right_Super     = 347,            // Key: Super right
	Kb_Menu         = 348,            // Key: KB menu
	// Keypad keys
	KP_0            = 320,            // Key: Keypad 0
	KP_1            = 321,            // Key: Keypad 1
	KP_2            = 322,            // Key: Keypad 2
	KP_3            = 323,            // Key: Keypad 3
	KP_4            = 324,            // Key: Keypad 4
	KP_5            = 325,            // Key: Keypad 5
	KP_6            = 326,            // Key: Keypad 6
	KP_7            = 327,            // Key: Keypad 7
	KP_8            = 328,            // Key: Keypad 8
	KP_9            = 329,            // Key: Keypad 9
	KP_Decimal      = 330,            // Key: Keypad .
	KP_Divide       = 331,            // Key: Keypad /
	KP_Multiply     = 332,            // Key: Keypad *
	KP_Subtract     = 333,            // Key: Keypad -
	KP_Add          = 334,            // Key: Keypad +
	KP_Enter        = 335,            // Key: Keypad Enter
	KP_Equal        = 336,            // Key: Keypad =
	// Android key buttons
	Back            = 4,              // Key: Android back button
	Menu            = 5,              // Key: Android menu button
	Volume_Up       = 24,             // Key: Android volume up button
	Volume_Down     = 25,             // Key: Android volume down button
}

Mouse_Button :: enum {
	MouseLeft,
	MouseRight,
	MouseMiddle,
	Side,
	Extra,
	Forward,
	Back,

	Wheel_Up,
	Wheel_Down,
}

Gamepad_Button :: enum {
	Unknown,                          // Unknown button, just for error checking
	Left_Face_Up,                     // Gamepad left DPAD up button
	Left_Face_Right,                  // Gamepad left DPAD right button
	Left_Face_Down,                   // Gamepad left DPAD down button
	Left_Face_Left,                   // Gamepad left DPAD left button
	Right_Face_Up,                    // Gamepad right button up (i.e. PS3: Triangle, Xbox: Y)
	Right_Face_Right,                 // Gamepad right button right (i.e. PS3: Circle, Xbox: B)
	Right_Face_Down,                  // Gamepad right button down (i.e. PS3: Cross, Xbox: A)
	Right_Face_Left,                  // Gamepad right button left (i.e. PS3: Square, Xbox: X)
	Left_Trigger_1,                   // Gamepad top/back trigger left (first), it could be a trailing button
	Left_Trigger_2,                   // Gamepad top/back trigger left (second), it could be a trailing button
	Right_Trigger_1,                  // Gamepad top/back trigger right (first), it could be a trailing button
	Right_Trigger_2,                  // Gamepad top/back trigger right (second), it could be a trailing button
	Middle_Left,                      // Gamepad center buttons, left one (i.e. PS3: Select)
	Middle,                           // Gamepad center buttons, middle one (i.e. PS3: PS, Xbox: XBOX)
	Middle_Right,                     // Gamepad center buttons, right one (i.e. PS3: Start)
	Left_Thumb,                       // Gamepad joystick pressed button left
	Right_Thumb,                      // Gamepad joystick pressed button right
}


// TODO: this is a terrible name
EventType :: union {
	Keyboard_Key,
	Mouse_Button,
	Gamepad_Button,
}


@private _EventState :: struct {
	time : time.Duration,
	down : bool,
}

@private _EventStates :: distinct map[EventType]_EventState


@private key_states     : _EventStates
@private mouse_states   : _EventStates
@private gamepad_states : _EventStates
// @private gamepad_axis_events  : map[InputEvent]_EventState     // TODO maybe

@private repeat_timer    : f64
@private repeat_cooldown : f64 = FIRST_REPEAT_COOLDOWN



// Test if one or more keys were just pressed this frame
key_pressed :: proc(keys: []Keyboard_Key) -> bool {
	for key in keys {
		if _event_pressed(key_states, key) do return true
	}
	return false
}

// Test if one or more keys were just released this frame
key_released :: proc(keys: []Keyboard_Key) -> bool {
	for key in keys {
		if _event_released(key_states, key) do return true
	}
	return false
}

// Test if one or more keys are being held down
key_down :: proc(keys: []Keyboard_Key) -> bool {
	for key in keys {
		if _event_down(key_states, key) do return true
	}
	return false
}

// Test if one or more keys are being repeated
key_repeat :: proc(keys: []Keyboard_Key) -> bool {
	for key in keys {
		if _event_repeat(key_states, key) do return true
	}
	return false
}



mouse_wheel :: proc() -> f32 {
	return rl.GetMouseWheelMove()
}

// Test if one or more mouse buttons were just clicked this frame
mouse_pressed :: proc(buttons: []Mouse_Button) -> bool {
	for btn in buttons {
		if _event_pressed(mouse_states, btn) do return true
	}
	return false
}

// Test if one or more mouse buttons were just released this frame
mouse_released :: proc(buttons: []Mouse_Button) -> bool {
	for btn in buttons {
		if _event_released(mouse_states, btn) do return true
	}
	return false
}

// Test if one or more mouse buttons are being held down
mouse_down :: proc(buttons: []Mouse_Button) -> bool {
	for btn in buttons {
		if _event_down(mouse_states, btn) do return true
	}
	return false
}

// Test if one or more mouse buttons are being repeated
mouse_repeat :: proc(buttons: []Mouse_Button) -> bool {
	for btn in buttons {
		if _event_repeat(mouse_states, btn) do return true
	}
	return false
}

// TODO: gamepad




@private _total_event_count :: proc() -> int {
	return len(key_states) + len(mouse_states) + len(gamepad_states)
}

@private _update_event_states :: proc(ev_states : ^_EventStates, dt: time.Duration) {
	for key, &event in ev_states {
		if !event.down do delete_key(ev_states, key)
		else           do event.time += dt
	}
}

@private _input_begin_frame :: proc(dt: time.Duration) {
	if _total_event_count() > 0 {
		if repeat_timer <= 0 {
			repeat_timer = repeat_cooldown
			repeat_cooldown = SECOND_REPEAT_COOLDOWN
		}
	}

	for event in mouse_states {
		if event == Mouse_Button.Wheel_Up || event == Mouse_Button.Wheel_Down {
			delete_key(&mouse_states, event)
		}
	}

	_update_event_states(&key_states, dt)
	_update_event_states(&mouse_states, dt)
	_update_event_states(&gamepad_states, dt)


	for k in rl.KeyboardKey {
		if rl.IsKeyPressed(k)  do _add_key_event(Keyboard_Key(k), true)
		if rl.IsKeyReleased(k) do _add_key_event(Keyboard_Key(k), false)
	}

	for b in rl.MouseButton {
		if rl.IsMouseButtonPressed(b) do _add_mouse_event(Mouse_Button(b), true)
		if rl.IsMouseButtonReleased(b) do _add_mouse_event(Mouse_Button(b), false)
	}

	// for b in rl.GamepadButton {
	// 	if rl.IsGamepadButtonPressed(b)  do _add_gamepad_event(Gamepad_Button(b), true)
	// 	if rl.IsGamepadButtonReleased(b) do _add_gamepad_event(Gamepad_Button(b), false)
	// }

	mw := rl.GetMouseWheelMove()
	if mw != 0 {
		if      mw < 0 do _add_mouse_event(Mouse_Button.Wheel_Down, true)
	 	else if mw > 0 do _add_mouse_event(Mouse_Button.Wheel_Up, true)
	}



	if _total_event_count() > 0 {
		repeat_timer -= time.duration_seconds(dt)
		if repeat_timer <= 0 do repeat_timer = 0
	} else {
		repeat_timer = 0
		repeat_cooldown = FIRST_REPEAT_COOLDOWN
	}

	_update_input_actions(dt)
}


@private _input_destroy :: proc() {
	_destroy_input_actions()
	delete(key_states)
	delete(mouse_states)
	delete(gamepad_states)
}


@private _add_key_event :: proc(key: Keyboard_Key, is_down: bool) {
	if key not_in key_states {
		key_states[key] = _EventState { down = is_down }
	} else {
		(&key_states[key]).down = is_down
	}
}

@private _add_mouse_event :: proc(button: Mouse_Button, is_down: bool) {
	button := Mouse_Button(button)

	if button not_in mouse_states {
		mouse_states[button] = _EventState { down = is_down }
	} else {
		(&mouse_states[button]).down = is_down
	}
}



@private _event_pressed :: proc(events: _EventStates, event: EventType) -> bool {
	return event in events && events[event].down && events[event].time == 0
}

@private _event_repeat :: proc(events: _EventStates, event: EventType) -> bool {
	return event in events && events[event].down && repeat_timer == 0
}

@private _event_down :: proc(events: _EventStates, event: EventType) -> bool {
	return event in events && events[event].down
}

@private _event_released :: proc(events: _EventStates, event: EventType) -> bool {
	return event in events && !events[event].down
}






/*******************************************************************************

		Input Actions

*******************************************************************************/
EventBind :: struct {
	event : EventType,
	mods  : ModKeySet,
}

ModKeys :: enum {
	Left_Control,
	Left_Shift,
	Left_Alt,
	Left_Super,
	Right_Control,
	Right_Shift,
	Right_Alt,
	Right_Super,
}

ModKeySet :: bit_set[ModKeys]

CTRL  :: ModKeySet{.Left_Control, .Right_Control}
SHFT  :: ModKeySet{.Left_Shift,   .Right_Shift}
ALT   :: ModKeySet{.Left_Alt,     .Right_Alt}
SUPER :: ModKeySet{.Left_Super,   .Right_Super}

CTRL_SHFT     :: ModKeySet{.Left_Control, .Right_Control, .Left_Shift, .Right_Shift}
CTRL_ALT      :: ModKeySet{.Left_Control, .Right_Control, .Left_Alt,   .Right_Alt}
SHFT_ALT      :: ModKeySet{.Left_Shift,   .Right_Shift,   .Left_Alt,   .Right_Alt}
CTRL_ALT_SHFT :: ModKeySet{.Left_Control, .Right_Control, .Left_Alt,   .Right_Alt,  .Left_Shift, .Right_Shift}


@private InputAction :: struct {
	name    : string,
	time    : time.Duration,
	binds   : [dynamic]EventBind,
}

@private actions          : map[string]InputAction
@private actions_pressed  : map[string]InputAction
@private actions_released : map[string]InputAction

@private action_repeat_timer    : f64
@private action_cooldown        : f64 = FIRST_REPEAT_COOLDOWN



// TODO: should these functions really crash, or just print out a warning?
action_pressed :: proc(name: string, loc := #caller_location ) -> bool {
	if name not_in actions do fmt.panicf(fmt="invalid action '%s'!", args={name}, loc=loc)
	return name in actions_pressed && actions_pressed[name].time == 0
}

action_down :: proc(name: string, loc := #caller_location ) -> bool {
	if name not_in actions do fmt.panicf(fmt="invalid action '%s'!", args={name}, loc=loc)
	return name in actions_pressed
}

action_released :: proc(name: string, loc := #caller_location ) -> bool {
	if name not_in actions do fmt.panicf(fmt="invalid action '%s'!", args={name}, loc=loc)
	return name in actions_released
}

action_repeat :: proc(name: string, loc := #caller_location ) -> bool {
	if name not_in actions do fmt.panicf(fmt="invalid action '%s'!", args={name}, loc=loc)
	return name in actions_pressed && action_repeat_timer == 0
}


add_bind :: proc(name: string, event: EventType) {
	add_bind_mod(name, EventBind{ event, {} })
}

add_binds :: proc(name: string, events: []EventType) {
	for e in events {
		add_bind_mod(name, EventBind{ e, {} })
	}
}

add_bind_mod :: proc(name: string, bind: EventBind) {
	if name not_in actions {
		actions[name] = InputAction { name = name }
	}
	action := &actions[name]
	append(&action.binds, bind)
}

add_binds_mod :: proc(name: string, binds: []EventBind) {
	for b in binds {
		add_bind_mod(name, b)
	}
}



@private _destroy_input_actions :: proc() {
	for _, &action in &actions {
		delete(action.binds)
	}

	delete(actions)
	delete(actions_pressed)
	delete(actions_released)
}


@private _update_input_actions :: proc(dt: time.Duration) {
	if len(actions_pressed) > 0 {
		if action_repeat_timer <= 0 {
			action_repeat_timer = action_cooldown
			action_cooldown = SECOND_REPEAT_COOLDOWN
		}
	}

	clear(&actions_released)

	for name, &action in actions_pressed {
		action.time += dt
	}

	for name, &action in actions {
		_check_action_pressed(&action)
		_check_action_released(&action)
	}

	if len(actions_pressed) > 0 {
		action_repeat_timer -= time.duration_seconds(dt)
		if action_repeat_timer <= 0 do action_repeat_timer = 0
	} else {
		action_repeat_timer = 0
		action_cooldown = FIRST_REPEAT_COOLDOWN
	}
}


@private _check_action_pressed :: proc(action: ^InputAction) {
	if action.name in actions_pressed do return
	binds_pressed := _check_binds_pressed(action)
	if binds_pressed {
		actions_pressed[action.name] = action^
		action.time = 0
		return
	}
}


@private _check_action_released :: proc(action: ^InputAction) {
	if action.name not_in actions_pressed do return

	binds_released := _check_binds_released(action)
	if binds_released {
		actions_released[action.name] = action^
		delete_key(&actions_pressed, action.name)
		action.time = 0
		return
	}
}


@private _check_binds_pressed :: proc(action: ^InputAction) -> bool {
	for bind in action.binds {
		is_pressed: bool
		switch event in bind.event {
			case Keyboard_Key:
				is_pressed = key_pressed({event})
				if _is_mod_key(event) && is_pressed do return true
			case Mouse_Button:
				is_pressed = mouse_pressed({event})
			case Gamepad_Button:
				// is_pressed = _gamepad_pressed({b.button})
		}

		if !is_pressed do continue
		mods_ok := _are_mods_ok(bind)
		if !mods_ok do continue
		return true
	}
	return false
}


@private _check_binds_released :: proc(action: ^InputAction) -> bool {
	for bind in action.binds {
		is_released: bool
		switch event in bind.event {
			case Keyboard_Key:   is_released = key_released({event})
			case Mouse_Button:   is_released = mouse_released({event})
			case Gamepad_Button:
		}

		if is_released do return true
		if !_are_mods_ok(bind) do return true
	}
	return false
}


@private _is_mod_key :: proc(input_value: EventType) -> bool {
	if key, ok := input_value.(Keyboard_Key); ok {
		// TODO: maybe this would be simpler with a bit set?
		#partial switch key {
			case .Left_Shift, .Left_Control, .Left_Alt, .Left_Super, \
			     .Right_Shift, .Right_Control, .Right_Alt, .Right_Super:
				return true
		}
	}
	return false
}


@private _are_mods_ok :: proc(b: EventBind) -> bool {
	if _, ok := b.event.(Gamepad_Button); ok do return true

	control_ok := _check_mod(b, .Left_Control, .Right_Control, .Left_Control, .Right_Control)
	shift_ok   := _check_mod(b, .Left_Shift,   .Right_Shift,   .Left_Shift,   .Right_Shift)
	alt_ok     := _check_mod(b, .Left_Alt,     .Right_Alt,     .Left_Alt,     .Right_Alt)

	return control_ok && shift_ok && alt_ok
}


@private _check_mod :: proc(b: EventBind, lmod, rmod: Keyboard_Key,
                            lbit, rbit: ModKeys) -> bool {
	ldown := key_down({lmod})
	rdown := key_down({rmod})

	if lbit in b.mods && rbit in b.mods {
		if !ldown && !rdown do return false
	} else if lbit in b.mods {
		if !ldown do return false
		if  rdown do return false
	} else if rbit in b.mods {
		if  ldown do return false
		if !rdown do return false
	} else {
		if ldown || rdown do return false
	}

	return true
}









