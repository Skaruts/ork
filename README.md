# Orc Roguelike Kit

A framework for developing text-based roguelikes in the Odin programming language.

TODO!

## Minimal Example

```odin
package main

import "ork"

console: ^ork.Console

main :: proc() {
	// Pass your callbacks to `ork.start`
	ork.start(init, tick, quit)
}

// Define your callbacks

init :: proc() {
	// Ork sets the window size based on the first console that is created.
	font := ork.new_font("my_font")
	console = ork.new_console(80, 45, font)
}

tick :: proc() {
	ork.draw_cell(console, 10, 10, '@', ork.BLUE6)
	ork.render(console)
}

// The `quit` callback is optional (you can pass `nil` to `ork.start` in its place).
quit :: proc() {}
```

