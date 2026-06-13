@echo off
REM Run the full GUT test suite headless and exit.
REM Requires `godot` on PATH (Godot 4.6.x).
REM cd into this script's own folder first so paths with spaces don't break args.
cd /d "%~dp0"
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
