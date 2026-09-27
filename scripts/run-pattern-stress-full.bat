@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "CONFIG=Release"
set "SEED="
if /I "%~1"=="Debug" (
  set "CONFIG=Debug"
  set "SEED=%~2"
) else if /I "%~1"=="Release" (
  set "CONFIG=Release"
  set "SEED=%~2"
) else (
  set "SEED=%~1"
)
call "%~dp0build-pattern-suite.bat" "%CONFIG%"
if errorlevel 1 exit /b 1
"%ROOT%\bin\Win64\%CONFIG%\TestPatternSearchStress.exe" --full %SEED%
exit /b %errorlevel%
