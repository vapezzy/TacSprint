@echo off
rem Startet den Prototyp mit der per winget installierten Godot-Version.
set "GODOT="
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do for %%G in ("%%D\Godot_v*_win64.exe") do set "GODOT=%%G"
if not defined GODOT (
	echo Godot wurde nicht gefunden. Installiere es mit: winget install GodotEngine.GodotEngine
	pause
	exit /b 1
)
if "%~1"=="--check" (
	echo %GODOT%
	exit /b 0
)
start "" "%GODOT%" --path "%~dp0."
