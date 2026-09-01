@echo off
setlocal
cd /d "%~dp0"
haxe -cp tools/src --run Run %*
