#!/usr/bin/env python3

import os
import subprocess
import argparse as ap
import time
import sys


# TODO
#    clean up command

VERSION  = 6

CWD       = os.getcwd()
CODE_PATH = "./examples"
OUT_DIR   = f"./examples/bin"
EXE_NAME  = "ork_examples"
DEBUGGER  = "remedybg"

MICROARC_ARG = "-microarch:x86-64"  # for old CPUs

BUILD_STR_DEBUG   = f"odin build {CODE_PATH} -out:{OUT_DIR}/{EXE_NAME}.exe {MICROARC_ARG} -debug"
BUILD_STR_RELEASE = f"odin build {CODE_PATH} -out:{OUT_DIR}/{EXE_NAME}.exe {MICROARC_ARG} -o:speed"

DISABLE_CONSOLE = False
NO_CONSOLE_ARG = "-subsystem:windows"

# Embed icon command, requires rcedit installed (or adapt to something else)
ICON_STR = f'rcedit "{OUT_DIR}/{EXE_NAME}.exe" --set-icon "_icon/icon.ico"'
NO_ICON  = True   # set to false to embed icon into executable


def print_command():
	print(BUILD_STR_DEBUG)
	print(BUILD_STR_RELEASE)


def clean_up():
	pass


def echo(msg):
	print(msg)
	sys.stdout.flush()


def run_executable():
	exe_path = os.path.join(CWD, f"{OUT_DIR}/{EXE_NAME}.exe" )
	if args.opt:
		subprocess.run( exe_path + " " + args.opt, shell=True, cwd=OUT_DIR)
	else:
		subprocess.run( exe_path, shell=True, cwd=OUT_DIR )


def compile(release:bool, run_app: bool):
	echo("compiling (debug)" if not release else "compiling (release)")
	comp_str = BUILD_STR_RELEASE if release else BUILD_STR_DEBUG
	if release and DISABLE_CONSOLE:
		comp_str = f"{comp_str} {NO_CONSOLE_ARG}"
	ret = subprocess.run(comp_str , shell=True, cwd=CWD, capture_output=False)
	if ret.returncode == 0:
		if not NO_ICON: embed_icon()
		if run_app: run_executable()


def run_debugger():
	echo("running {DEBUGGER}")
	proc = subprocess.Popen([DEBUGGER], shell=True,
		   stdin=None, stdout=None, stderr=None, close_fds=True)




def embed_icon():
	echo("embeding icon")
	subprocess.run(ICON_STR , shell=True, cwd=CWD)


class CustomFormatter(ap.HelpFormatter):
	def _split_lines(self, text, width):
		return text.splitlines()


if __name__ == "__main__":
	parser = ap.ArgumentParser(formatter_class=CustomFormatter)
	parser.add_argument("-v", "--version", action="version", version=f"Project compiler/runner (Version {VERSION})\n\n", help="Show this script's version.\n")

	parser.add_argument("-c", "--clean", action="store_true", help="clean up\n")

	parser.add_argument("-d", "-rd", "--debug", action="store_true", help="compile and run in debug mode\n")
	parser.add_argument("-r", "-rr", "--release", action="store_true", help="compile and run in release mode\n")
	parser.add_argument("-bd", "--build_debug", action="store_true", help="compile in debug mode\n")
	parser.add_argument("-br", "--build_release", action="store_true", help="compile in release mode\n")

	parser.add_argument("-dbg", "--debugger", action="store_true", help="run debugger\n")
	parser.add_argument("-ic", "--icon", action="store_true", help="embed icon in exe\n")
	parser.add_argument("-p", "--print", action="store_true", help="print out the compile commands\n")

	parser.add_argument("opt", const=None, nargs='?')

	args = parser.parse_args()

	if   args.clean:         clean_up()
	elif args.debug:         compile(False, True)
	elif args.build_debug:   compile(False, False)
	elif args.release:       compile(True,  True)
	elif args.build_release: compile(True,  False)
	elif args.debugger:      run_debugger()
	elif args.icon:          embed_icon()
	elif args.print:         print_command()
	else:                    run_executable()




