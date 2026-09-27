@echo off
setlocal EnableExtensions
call "%~dp0run-pattern-tests.bat" Debug
if errorlevel 1 exit /b 1
call "%~dp0run-pattern-tests.bat" Release full
if errorlevel 1 exit /b 1
call "%~dp0run-pattern-benchmark.bat" Release full
exit /b %errorlevel%
