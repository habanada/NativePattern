@echo off
setlocal EnableExtensions
set "CONFIG=Release"
set "MODE="
if /I "%~1"=="Debug" set "CONFIG=Debug"
if /I "%~1"=="Release" set "CONFIG=Release"
if /I "%~1"=="full" set "MODE=full"
if /I "%~2"=="full" set "MODE=full"
call "%~dp0run-pattern-tests.bat" "%CONFIG%" %MODE%
if errorlevel 1 exit /b 1
call "%~dp0run-pattern-benchmark.bat" "%CONFIG%" %MODE%
exit /b %errorlevel%
