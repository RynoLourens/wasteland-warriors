@echo off
REM Launch Wasteland Warriors (main scene = SetupScreen.tscn).
REM Requires `godot` on PATH (Godot 4.6.x).
REM cd into this script's own folder first so paths with spaces don't break args.
cd /d "%~dp0"
godot
