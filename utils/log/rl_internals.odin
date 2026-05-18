package logger

import "core:os"


/*
	Some helper procs to make it easier to use the internal logger
	to prevent mistakes. The Orc user api mirrors
	this, but for the 'user_logger'. (This is not part of the logger itself,
	I just made it for Orc)
*/


__print :: proc(args: ..any, loc := #caller_location) {
	print(logger=_default_logger, args=args, loc=loc)
}

__printf :: proc(msg:string, args: ..any, loc := #caller_location) {
	printf(logger=_default_logger, msg=msg, args=args, loc=loc)
}

__info :: proc(msg:string, args: ..any, loc := #caller_location) {
	info(logger=_default_logger, msg=msg, args=args, loc=loc)
}

__task :: proc(msg:string, args: ..any, loc := #caller_location) {
	task(logger=_default_logger, msg=msg, args=args, loc=loc)
}

__reminder :: proc(msg:string, args: ..any, loc := #caller_location) {
	reminder(logger=_default_logger, msg=msg, args=args, loc=loc)
}

__deprecated :: proc(msg:string, args: ..any, loc := #caller_location) {
	deprecated(logger=_default_logger, msg=msg, args=args, loc=loc)
}

__warning :: proc(msg:string, args: ..any, loc := #caller_location) {
	warning(logger=_default_logger, msg=msg, args=args, loc=loc)
}

__error :: proc(msg:string, args: ..any, loc := #caller_location) {
	error(logger=_default_logger, msg=msg, args=args, loc=loc)
}

__error_quit :: proc(msg:string, args: ..any, loc := #caller_location) {
	error(logger=_default_logger, msg=msg, args=args, loc=loc)
	os.exit(1)
}
