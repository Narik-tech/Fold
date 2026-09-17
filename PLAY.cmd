@echo off
cd /d "%~dp0"
if exist ".tools\godot\Godot_v4.6-stable_win64.exe" (
  start "FOLD" ".tools\godot\Godot_v4.6-stable_win64.exe" --path "%~dp0." --log-file "%~dp0.tools\game.log"
) else (
  where godot >nul 2>nul
  if errorlevel 1 (
    echo Open project.godot in Godot 4.3 or newer and press F5.
    pause
  ) else (
    start "FOLD" godot --path "%~dp0."
  )
)
