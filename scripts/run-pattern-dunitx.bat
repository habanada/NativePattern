@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "CONFIG=Release"
if /I "%~1"=="Debug" set "CONFIG=Debug"
if /I "%~1"=="Release" set "CONFIG=Release"
call "%~dp0build-pattern-suite.bat" "%CONFIG%"
if errorlevel 1 exit /b 1
set "RESULTS=%ROOT%\test-results"
if not exist "%RESULTS%" mkdir "%RESULTS%"
set "NATIVEPE_DUNITX_XML=%RESULTS%\PatternSearchDUnitX-%CONFIG%.xml"
"%ROOT%\bin\Win64\%CONFIG%\PatternSearchDUnitX.exe"
exit /b %errorlevel%
