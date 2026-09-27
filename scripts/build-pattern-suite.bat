@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "CONFIG=Release"
if /I "%~1"=="Debug" set "CONFIG=Debug"
if /I "%~1"=="Release" set "CONFIG=Release"
if not "%~1"=="" if /I not "%~1"=="Debug" if /I not "%~1"=="Release" (
  echo Invalid configuration "%~1". Use Debug or Release.
  exit /b 2
)

if not defined BDS if exist "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat" call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
where dcc64 >nul 2>nul
if errorlevel 1 (
  echo dcc64.exe not found. Run this from a RAD Studio command prompt or install Delphi 23.0.
  exit /b 1
)

set "BIN=%ROOT%\bin\Win64\%CONFIG%"
set "DCU=%ROOT%\dcu\Win64\%CONFIG%"
set "SRC=%ROOT%\src"
set "TESTS=%ROOT%\tests"
set "DUNITX=%DUNITX_PATH%"
if not defined DUNITX if defined BDS if exist "%BDS%\source\DUnitX\Source\DUnitX.TestFramework.pas" set "DUNITX=%BDS%\source\DUnitX\Source"
if not defined DUNITX if defined BDS if exist "%BDS%\source\DUnitX\DUnitX.TestFramework.pas" set "DUNITX=%BDS%\source\DUnitX"

if /I "%CONFIG%"=="Debug" (
  set "MODEFLAGS=-DDEBUG -$O- -$D+ -$L+ -$R+ -$Q+"
) else (
  set "MODEFLAGS=-DRELEASE -$O+ -$D- -$L- -$R- -$Q-"
)

if not exist "%BIN%" mkdir "%BIN%"
if exist "%DCU%" rmdir /s /q "%DCU%"
mkdir "%DCU%"
del /q "%BIN%\TestPatternSearch.exe" "%BIN%\TestPatternSearchRandom.exe" "%BIN%\TestPatternSearchStress.exe" "%BIN%\PatternSearchDUnitX.exe" "%BIN%\PatternSearchBenchmark.exe" >nul 2>nul

echo Building %CONFIG% deterministic console tests...
pushd "%TESTS%"
dcc64 -B -Q -TX.exe %MODEFLAGS% -E"%BIN%" -N0"%DCU%" -U"%SRC%" TestPatternSearch.dpr
if errorlevel 1 goto :fail
dcc64 -B -Q -TX.exe %MODEFLAGS% -E"%BIN%" -N0"%DCU%" -U"%SRC%" TestPatternSearchRandom.dpr
if errorlevel 1 goto :fail
dcc64 -B -Q -TX.exe %MODEFLAGS% -E"%BIN%" -N0"%DCU%" -U"%SRC%" TestPatternSearchStress.dpr
if errorlevel 1 goto :fail
popd

echo Building %CONFIG% DUnitX suite...
pushd "%TESTS%\dunitx"
if defined DUNITX (
  dcc64 -B -Q -TX.exe %MODEFLAGS% -E"%BIN%" -N0"%DCU%" -U"%SRC%;%DUNITX%" PatternSearchDUnitX.dpr
) else (
  dcc64 -B -Q -TX.exe %MODEFLAGS% -E"%BIN%" -N0"%DCU%" -U"%SRC%" PatternSearchDUnitX.dpr
)
if errorlevel 1 (
  echo DUnitX build failed. If DUnitX is not on the Delphi library path, set DUNITX_PATH to its Source directory.
  goto :fail
)
popd

echo Building %CONFIG% benchmark...
pushd "%ROOT%\benchmarks"
dcc64 -B -Q -TX.exe %MODEFLAGS% -E"%BIN%" -N0"%DCU%" -U"%SRC%" PatternSearchBenchmark.dpr
if errorlevel 1 goto :fail
popd

echo Pattern suite build OK: %BIN%
exit /b 0

:fail
popd >nul 2>nul
exit /b 1
