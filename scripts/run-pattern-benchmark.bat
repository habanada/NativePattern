@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "CONFIG=Release"
set "MODE="
set "TAG=quick"
if /I "%~1"=="Debug" set "CONFIG=Debug"
if /I "%~1"=="Release" set "CONFIG=Release"
if /I "%~1"=="full" set "MODE=--full"
if /I "%~2"=="full" set "MODE=--full"
if defined MODE set "TAG=full"
call "%~dp0build-pattern-suite.bat" "%CONFIG%"
if errorlevel 1 exit /b 1
set "RESULTS=%ROOT%\test-results"
if not exist "%RESULTS%" mkdir "%RESULTS%"
"%ROOT%\bin\Win64\%CONFIG%\PatternSearchBenchmark.exe" %MODE% --csv="%RESULTS%\pattern-benchmark-%CONFIG%-%TAG%.csv"
exit /b %errorlevel%
