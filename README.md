# Ork Roguelike Kit

A framework for developing text-based roguelikes in [Odin](https://odin-lang.org/). It provides consoles for rendering text, FOV algorithms, and more.

TODO!


## Usage

Ork aims to remove most boilerplate code needed to start a project, and to keep track of its own memory allocations, so it can clean up after itself.

It takes some inspiration from fantasy consoles. You define three callbacks for your game, and Ork will take care of the rest.

This is how a bare-bones Ork project looks like:

```odin
package main

import "ork"

console: ^ork.Console

main :: proc() {
	// Pass your callbacks to `ork.start()`
	ork.start(init, tick, quit)
}

// Define your callbacks

init :: proc() {
	// Initialize your game here. It's important that
	// you create at least one console during this phase, as Ork sets
	// the window size based on the first console that is created.

	console = ork.new_console(80, 45)
}

tick :: proc() {
	// Update your game and render your consoles.

	ork.draw_cell(console, 10, 10, '@', ork.BLUE6)
	ork.render(console)
}

quit :: proc() {
	// Close things up, free memory allocations, etc.

	// The `quit` callback is optional. You can pass `nil` to `ork.start`
	// in its place, if you don't need it.
}
```

## Building The Examples

The `build.py` script should make it easy to build and run the examples inside the `_examples` folder. You can run it with `-d` or `-r` arguments to build and run in debug or release modes, or with `-h` to see other options.

Running it without arguments runs the last compiled executable.

The executable is generated inside `"_examples/bin"`, which already contains some fonts and images used by the examples.



## Attribution

Default font, and fonts used in the examples, courtezy of [Kyzrati from GridSageGames](https://www.reddit.com/r/roguelikedev/comments/c52ik4/comment/es4sxdc/?utm_source=share&utm_medium=web2x&context=3) (creator of REXPaint).
