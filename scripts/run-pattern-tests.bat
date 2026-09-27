@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "CONFIG=Release"
set "MODE="
if /I "%~1"=="Debug" set "CONFIG=Debug"
if /I "%~1"=="Release" set "CONFIG=Release"
if /I "%~1"=="full" set "MODE=--full"
if /I "%~2"=="full" set "MODE=--full"
call "%~dp0build-pattern-suite.bat" "%CONFIG%"
if errorlevel 1 exit /b 1
set "BIN=%ROOT%\bin\Win64\%CONFIG%"
set "RESULTS=%ROOT%\test-results"
if not exist "%RESULTS%" mkdir "%RESULTS%"

"%BIN%\TestPatternSearch.exe"
if errorlevel 1 exit /b 1
"%BIN%\TestPatternSearchRandom.exe"
if errorlevel 1 exit /b 1
set "NATIVEPE_DUNITX_XML=%RESULTS%\PatternSearchDUnitX-%CONFIG%.xml"
"%BIN%\PatternSearchDUnitX.exe"
if errorlevel 1 exit /b 1
"%BIN%\TestPatternSearchStress.exe" %MODE%
if errorlevel 1 exit /b 1

echo ALL PATTERN TEST SUITES PASSED
exit /b 0
