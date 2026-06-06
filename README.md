# Ork Roguelike Kit

Ork is a framework for developing text-based roguelikes in the [Odin Programming Language](https://odin-lang.org/). It provides consoles for rendering text, FOV algorithms, a REXPaint image loader, and more, through a simple to use API that was vaguely inspired by those of fantasy consoles.

###### Note: this is still in very early development and is also an experimental learning project for me, so some things are not yet polished or definitive.

Please check out the code in the examples for a more in depth view of how it works (see [Building The Examples](#building-the-examples)).

<img width="1598" height="920" alt="Ork_03" src="https://github.com/user-attachments/assets/ddae7fbf-72e2-44c1-9a01-04820bf6111c" />


## Usage

Ork attempts to reduce the boilerplate code needed to start a project, and to keep track of its own memory allocations, so it can clean up after itself. At the most basic level, all you have to do is define three callbacks for your game and create at least one console. 

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
	ork.set_window_title("Minimal Example Title")

	// Initialize your game here. It's important that
	// you create at least one console during this phase, as Ork sets
	// the window size based on the first console that is created.

	console = ork.new_console(80, 45)  // no font is provided, so it uses the default one
}

tick :: proc() {
	// Update your game and render your consoles.

	ork.draw_cell(console, 10, 10, '@', ork.BLUE6)
	ork.render(console)
}

quit :: proc() {
	// Close things up, free memory allocations, etc.

	// There's no need to delete/free the console, as it's freed internally by Ork.

	// The `quit` callback is optional. You can pass `nil` to `ork.start`
	// in its place, if you don't need it.
}
```

## Building The Examples

The `build.py` script should make it easy to build and run the examples inside the `examples` folder. You can run it with `-d` or `-r` arguments to build and run in debug or release modes, or with `-h` to see other options.

Running it without arguments runs the last compiled executable.

The executable is generated inside `"examples/bin"`, which already contains some fonts and images used by the examples.



## Attribution

Default font, and fonts used in the examples, [courtezy of Kyzrati](https://www.reddit.com/r/roguelikedev/comments/c52ik4/comment/es4sxdc/?utm_source=share&utm_medium=web2x&context=3) of [GridSageGames](https://www.gridsagegames.com) (creator of [REXPaint](https://www.gridsagegames.com/rexpaint)).


