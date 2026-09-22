@echo off
rem Запуск выделенного сервера на Windows.
rem Укажи путь к консольному Godot (Godot_v4.3-stable_win64_console.exe)
if "%GODOT_BIN%"=="" set GODOT_BIN=godot
"%GODOT_BIN%" --headless --path "%~dp0..\server" %*
pause
