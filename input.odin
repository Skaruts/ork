#+feature dynamic-literals
package ork


import "core:time"
import "core:fmt"

import k2 "libs/karl2d"



FIRST_REPEAT_COOLDOWN  :: 0.28 // 0.25
SECOND_REPEAT_COOLDOWN :: 0.08 // 0.05

Keyboard_Key   :: k2.Keyboard_Key

Mouse_Button :: enum {
	MouseLeft,         // override Karl2d names to not conflict with arrow keys
	MouseRight,        // when using implicit selectors (`.Left`) in 'add_bind'.
	MouseMiddle,       // (Mouse_Button.Left vs Keyboard_Key.Left)
	Wheel_Up   = 253,
	Wheel_Down = 254,
	Max        = 255,
}

Gamepad_Button :: k2.Gamepad_Button


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
	return k2.get_mouse_wheel_delta()
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

	events := k2.get_events()
	for &event in events {
		_store_event(&event)
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


@private _add_key_event :: proc(event: ^k2.Event, key: Keyboard_Key,
	                            is_down: bool) {
	key := Keyboard_Key(key)

	if key not_in key_states {
		key_states[key] = _EventState {
			down = is_down
		}
	} else {
		evst := &key_states[key]
		evst.down = is_down
	}
}

@private _add_mouse_event :: proc(event: ^k2.Event, button: Mouse_Button,
	                              is_down: bool) {
	button := Mouse_Button(button)

	if button not_in mouse_states {
		mouse_states[button] = _EventState {
			down = is_down
		}
	} else {
		evst := &mouse_states[button]
		evst.down = is_down
	}
}


@private _store_event :: proc(event: ^k2.Event) {
	event := event
	#partial switch &e in event {
		// case Event_Close_Window_Requested:

		case k2.Event_Key_Went_Down: _add_key_event(event, e.key, true)
		case k2.Event_Key_Went_Up:   _add_key_event(event, e.key, false)

		case k2.Event_Mouse_Button_Went_Down: _add_mouse_event(event, Mouse_Button(e.button), true)
		case k2.Event_Mouse_Button_Went_Up:   _add_mouse_event(event, Mouse_Button(e.button), false)

		case k2.Event_Mouse_Wheel:
			if      e.delta < 0 do _add_mouse_event(event, Mouse_Button.Wheel_Down, true)
			else if e.delta > 0 do _add_mouse_event(event, Mouse_Button.Wheel_Up, true)

		// case Event_Mouse_Move:

		// case Event_Gamepad_Button_Went_Down:
		// case Event_Gamepad_Button_Went_Up:

		// case Event_Screen_Resize:
		// case Event_Window_Focused:
		// case Event_Window_Unfocused:
		// case Event_Window_Scale_Changed:
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

	#partial switch event in b.event {
		case Keyboard_Key: if b.mods == {} do return true
		case Mouse_Button: if b.mods == {} do return true
	}

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









