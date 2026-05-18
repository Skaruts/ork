/*******************************************************************************
			Logger  (version 23)

	A custom logger. Unfortunately it can't go in 'context'.

*******************************************************************************/


package logger

import "core:sys/windows"
import "core:fmt"
import "core:slice"
import "core:path/filepath"
// import "core:strings"
import "core:terminal"
import "core:terminal/ansi"



LOCATION   :: ansi.CSI + ansi.FG_BRIGHT_BLUE    + ansi.SGR
INFO       :: ansi.CSI + ansi.FG_BRIGHT_CYAN    + ansi.SGR
TASK       :: ansi.CSI + ansi.FG_BRIGHT_GREEN   + ansi.SGR
REMINDER   :: ansi.CSI + ansi.FG_BRIGHT_MAGENTA + ansi.SGR
DEPRECATED :: ansi.CSI + ansi.FG_YELLOW         + ansi.SGR
WARNING    :: ansi.CSI + ansi.FG_BRIGHT_YELLOW  + ansi.SGR
ERROR      :: ansi.CSI + ansi.FG_BRIGHT_RED     + ansi.SGR
RESET      :: ansi.CSI + ansi.RESET             + ansi.SGR


@private LogLevel :: enum uint {
	Print,  // regular print statements, but through the logger, with location info
	Printf,
	Info,
	Task,
	Reminder,
	Deprecated,
	Warning,
	Error,
}


Logger :: struct {
	send_to_file    : bool, // N/A yet
	send_to_stdout  : bool,
	print_locations : bool,
	other_locations : bool,  // show locations of errors, warnings, anything that isn't 'print'

	log_prints      : bool,
	log_infos       : bool,
	log_tasks       : bool,
	log_reminders   : bool,
	log_deprecateds : bool,
	log_warnings    : bool,
	log_errors      : bool,

	prints          : [dynamic]string,
	infos           : [dynamic]string,
	tasks           : [dynamic]string,
	reminders       : [dynamic]string,
	deprecateds     : [dynamic]string,
	warnings        : [dynamic]string,
	errors          : [dynamic]string,
}


@private _loggers : [dynamic]^Logger
@private _curr_logger : ^Logger
@private _default_logger : ^Logger

/*******************************************************************************
		logging start / end
*/
begin :: proc() {
	when ODIN_OS == .Windows {
		windows.SetConsoleOutputCP(.UTF8)
	}

	_default_logger = new_logger()
	_curr_logger = _default_logger
}

end :: proc() {
	#reverse for &logger in _loggers {
		destroy_logger(logger)
	}
	delete(_loggers)
}



/*******************************************************************************
		logger init / detroy
*/
new_logger :: proc () -> ^Logger {
	logger := new(Logger)

	logger.send_to_stdout    = true
	logger.send_to_file      = false // N/A yet
	logger.print_locations   = true
	logger.other_locations   = false

	logger.log_prints        = true
	logger.log_infos         = true
	logger.log_tasks         = true
	logger.log_reminders     = true
	logger.log_deprecateds   = true
	logger.log_warnings      = true
	logger.log_errors        = true

	append(&_loggers, logger)
	return logger
}

destroy_logger :: proc(logger:^Logger) {
	delete(logger.prints)
	delete(logger.infos)
	delete(logger.tasks)
	delete(logger.reminders)
	delete(logger.deprecateds)
	delete(logger.warnings)
	delete(logger.errors)

	idx, _ := slice.linear_search(_loggers[:], logger)
	unordered_remove(&_loggers, idx)

	free(logger)
}

set_current_logger :: proc(logger: ^Logger) {
	_curr_logger = logger
}

get_current_logger :: proc() -> ^Logger {
	return _curr_logger
}

/*******************************************************************************
		message printing
*/
@private _build_prefix :: proc(logger: ^Logger, level: LogLevel, loc := #caller_location) -> string {
	loc_str := ""
	str: string

	if terminal.color_enabled {
		switch level {
			case .Print, .Printf:
				if logger.print_locations do loc_str = fmt.tprintf("%s%s(%d): ", LOCATION,   filepath.base(loc.file_path), loc.line)
				str = loc_str
			case .Info:
				if logger.other_locations do loc_str = fmt.tprintf("%s%s(%d): ", INFO,       filepath.base(loc.file_path), loc.line)
				str = fmt.tprintf( "%s%s%s: ", loc_str, INFO,       "INFO"       )
			case .Task:
				if logger.other_locations do loc_str = fmt.tprintf("%s%s(%d): ", TASK,       filepath.base(loc.file_path), loc.line)
				str = fmt.tprintf( "%s%s%s: ", loc_str, TASK,       "TASK"       )
			case .Reminder:
				if logger.other_locations do loc_str = fmt.tprintf("%s%s(%d): ", REMINDER,   filepath.base(loc.file_path), loc.line)
				str = fmt.tprintf( "%s%s%s: ", loc_str, REMINDER,   "REMINDER"   )
			case .Deprecated:
				if logger.other_locations do loc_str = fmt.tprintf("%s%s(%d): ", DEPRECATED, filepath.base(loc.file_path), loc.line)
				str = fmt.tprintf( "%s%s%s: ", loc_str, DEPRECATED, "DEPRECATED" )
			case .Warning:
				if logger.other_locations do loc_str = fmt.tprintf("%s%s(%d): ", WARNING,    filepath.base(loc.file_path), loc.line)
				str = fmt.tprintf( "%s%s%s: ", loc_str, WARNING,    "WARNING"    )
			case .Error:
				if logger.other_locations do loc_str = fmt.tprintf("%s%s(%d): ", ERROR,      filepath.base(loc.file_path), loc.line)
				str = fmt.tprintf( "%s%s%s: ", loc_str, ERROR,      "ERROR"      )
		}
	} else {
		if level <= .Printf && logger.print_locations || level > .Printf && logger.other_locations {
			loc_str = fmt.tprintf("%s(%d): ", filepath.base(loc.file_path), loc.line)
		}

		switch level {
			case .Print, .Printf: str = loc_str
			case .Info:       str = fmt.tprintf( "%s%s: ", loc_str, "INFO"       )
			case .Task:       str = fmt.tprintf( "%s%s: ", loc_str, "TASK"       )
			case .Reminder:   str = fmt.tprintf( "%s%s: ", loc_str, "REMINDER"   )
			case .Deprecated: str = fmt.tprintf( "%s%s: ", loc_str, "DEPRECATED" )
			case .Warning:    str = fmt.tprintf( "%s%s: ", loc_str, "WARNING"    )
			case .Error:      str = fmt.tprintf( "%s%s: ", loc_str, "ERROR"      )
		}
	}

	return str
}

@private _log_message :: proc(logger: ^Logger, level: LogLevel, msg: string, args: ..any, loc := #caller_location) {
	usr_str  := len(args) > 0 ? fmt.tprintf(msg, ..args) : msg
	prefix   := _build_prefix(logger, level, loc)
	full_str :string

	if terminal.color_enabled {
		if level <= .Printf do full_str = fmt.tprintf("%s%s%s", prefix, RESET, usr_str)
		else                do full_str = fmt.tprintf("%s%s%s", prefix, usr_str, RESET)
	} else {
		full_str = fmt.tprintf("%s%s", prefix, usr_str)
	}

	array: ^[dynamic]string
	switch level {
		case .Print, .Printf: array = &logger.prints
		case .Info:           array = &logger.infos
		case .Task:           array = &logger.tasks
		case .Reminder:       array = &logger.reminders
		case .Deprecated:     array = &logger.deprecateds
		case .Warning:        array = &logger.warnings
		case .Error:          array = &logger.errors
	}
	append(array, full_str)

	if !logger.send_to_stdout do return

	if level != .Error do fmt.println(full_str)
	else               do fmt.eprintln(full_str)
}



/*******************************************************************************
		log_print

	Like println, but with filename and line number prefixed
*/
@private _logger_print_impl :: proc(logger: ^Logger, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_prints do return
	msg := fmt.tprint(..args)
	_log_message(logger=logger, level=.Print, msg=msg, args={}, loc=loc)
}

@private _logger_print_nl :: proc(args: ..any, loc := #caller_location) {
	_logger_print_impl(logger=_curr_logger, args=args, loc=loc)
}

print :: proc {_logger_print_impl, _logger_print_nl}



/*******************************************************************************
		log_printf
*/
@private _logger_printf_impl :: proc(logger:^Logger, msg:string, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_prints do return
	_log_message(logger=logger, level=.Printf, msg=msg, args=args, loc=loc)
}

@private _logger_printf_nl :: proc(msg:string, args: ..any, loc := #caller_location) {
	_logger_printf_impl(logger=_curr_logger, msg=msg, args=args, loc=loc)
}

printf :: proc { _logger_printf_impl, _logger_printf_nl }



/*******************************************************************************
		log_info
*/
@private _logger_info_impl :: proc(logger:^Logger, msg:string, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_infos do return
	_log_message(logger=logger, level=.Info, msg=msg, args=args, loc=loc)
}

@private _logger_info_nl :: proc(msg:string, args: ..any, loc := #caller_location) {
	_logger_info_impl(logger=_curr_logger, msg=msg, args=args, loc=loc)
}

info :: proc { _logger_info_impl, _logger_info_nl }



/*******************************************************************************
		log_task
*/
@private _logger_task_impl :: proc(logger:^Logger, msg:string, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_tasks do return
	_log_message(logger=logger, level=.Task, msg=msg, args=args, loc=loc)
}

@private _logger_task_nl :: proc(msg:string, args: ..any, loc := #caller_location) {
	_logger_task_impl(logger=_curr_logger, msg=msg, args=args, loc=loc)
}

task :: proc { _logger_task_impl, _logger_task_nl }



/*******************************************************************************
		log_reminder
*/
@private _logger_reminder_impl :: proc(logger:^Logger, msg:string, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_reminders do return
	_log_message(logger=logger, level=.Reminder, msg=msg, args=args, loc=loc)
}

@private _logger_reminder_nl :: proc(msg:string, args: ..any, loc := #caller_location) {
	_logger_reminder_impl(logger=_curr_logger, msg=msg, args=args, loc=loc)
}

reminder :: proc { _logger_reminder_impl, _logger_reminder_nl }



/*******************************************************************************
		log_deprecated
*/
@private _logger_deprecated_impl :: proc(logger:^Logger, msg:string, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_deprecateds do return
	_log_message(logger=logger, level=.Deprecated, msg=msg, args=args, loc=loc)
}

@private _logger_deprecated_nl :: proc(msg:string, args: ..any, loc := #caller_location) {
	_logger_deprecated_impl(logger=_curr_logger, msg=msg, args=args, loc=loc)
}

deprecated :: proc { _logger_deprecated_impl, _logger_deprecated_nl }



/*******************************************************************************
		log_warning
*/
@private _logger_warning_impl :: proc(logger:^Logger, msg:string, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_warnings do return
	_log_message(logger=logger, level=.Warning, msg=msg, args=args, loc=loc)
}

@private _logger_warning_nl :: proc(msg:string, args: ..any, loc := #caller_location) {
	_logger_warning_impl(logger=_curr_logger, msg=msg, args=args, loc=loc)
}

warning :: proc { _logger_warning_impl, _logger_warning_nl }



/*******************************************************************************
		log_error
*/
@private _logger_error_impl :: proc(logger:^Logger, msg:string, args: ..any, loc := #caller_location) {
	assert(logger != nil)
	if !logger.log_errors do return
	_log_message(logger=logger, level=.Error, msg=msg, args=args, loc=loc)
}

@private _logger_error_nl :: proc(msg:string, args: ..any, loc := #caller_location) {
	_logger_error_impl(logger=_curr_logger, msg=msg, args=args, loc=loc)
}

error :: proc { _logger_error_impl, _logger_error_nl }


