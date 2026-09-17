@echo off
cd /d "%~dp0"
if exist ".tools\godot\Godot_v4.6-stable_win64.exe" (
  start "FOLD Level Editor" ".tools\godot\Godot_v4.6-stable_win64.exe" --editor --path "%~dp0."
) else (
  where godot >nul 2>nul
  if errorlevel 1 (
    echo Open project.godot in Godot 4.6 or newer and select FOLD Levels.
    pause
  ) else (
    start "FOLD Level Editor" godot --editor --path "%~dp0."
  )
)
