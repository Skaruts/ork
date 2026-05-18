# Ork Roguelike Kit

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

## Building The Examples

The `build.py` script should make it easy to build and run the examples inside the `_examples` folder. You can run it with `-d` or `-r` arguments to build and run in debug or release modes, or with `-h` to see other options.

Running it without arguments runs the last compiled executable.

The executable is generated inside `"_examples/bin"`, which already contains some fonts and images used by the examples.

## Attribution

Default font, and fonts used in the examples, courtezy of [Kyzrati from GridSageGames](https://www.reddit.com/r/roguelikedev/comments/c52ik4/comment/es4sxdc/?utm_source=share&utm_medium=web2x&context=3) (creator of REXPaint).
