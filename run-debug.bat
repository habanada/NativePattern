@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "BIN=%ROOT%\bin\Win64\Debug"
set "RESULTS=%ROOT%\test-results"

if not exist "%BIN%" (
  echo Debug-Verzeichnis nicht gefunden:
  echo   %BIN%
  exit /b 2
)

if not exist "%RESULTS%" mkdir "%RESULTS%"

if not "%~1"=="" goto commandline

:menu
cls
echo NativePattern Win64 Debug Launcher
echo.
echo   1  Alle Pattern-Tests ^(inkl. DUnitX + Quick-Stress^)
echo   2  Pattern DUnitX
echo   3  Pattern deterministisch
echo   4  Pattern Random
echo   5  Pattern Stress Quick
echo   6  Pattern Stress Full
echo   7  Pattern Benchmark Quick
echo   8  Pattern Benchmark Full
echo   9  Einzelne EXE starten
echo  10  Vorhandene EXEs anzeigen
echo   0  Beenden
echo.
set "SEL="
set /p "SEL=Auswahl: "

if "%SEL%"=="1" call :run_pattern_tests
if "%SEL%"=="2" call :run_dunitx
if "%SEL%"=="3" call :run_noargs "TestPatternSearch.exe"
if "%SEL%"=="4" call :run_noargs "TestPatternSearchRandom.exe"
if "%SEL%"=="5" call :run_stress_quick
if "%SEL%"=="6" call :run_stress_full_prompt
if "%SEL%"=="7" call :run_benchmark_quick
if "%SEL%"=="8" call :run_benchmark_full
if "%SEL%"=="9" call :run_custom_prompt
if "%SEL%"=="10" call :list_exes
if "%SEL%"=="0" exit /b 0

echo.
pause
goto menu

:commandline
if /I "%~1"=="tests" goto cmd_pattern
if /I "%~1"=="pattern" goto cmd_pattern
if /I "%~1"=="dunitx" goto cmd_dunitx
if /I "%~1"=="stress" goto cmd_stress
if /I "%~1"=="benchmark" goto cmd_benchmark
if /I "%~1"=="list" goto cmd_list
goto usage

:cmd_pattern
call :run_pattern_tests
exit /b %ERRORLEVEL%

:cmd_dunitx
call :run_dunitx
exit /b %ERRORLEVEL%

:cmd_stress
if /I "%~2"=="full" (
  set "SEEDARG="
  if not "%~3"=="" set "SEEDARG=--seed=%~3"
  call :run_stress_full
  exit /b %ERRORLEVEL%
)
call :run_stress_quick
exit /b %ERRORLEVEL%

:cmd_benchmark
if /I "%~2"=="full" (
  call :run_benchmark_full
  exit /b %ERRORLEVEL%
)
call :run_benchmark_quick
exit /b %ERRORLEVEL%

:cmd_list
call :list_exes
exit /b 0

:usage
echo NativePattern Win64 Debug Launcher
echo.
echo Verwendung:
echo   run-debug.bat
echo   run-debug.bat tests
echo   run-debug.bat pattern
echo   run-debug.bat dunitx
echo   run-debug.bat stress
echo   run-debug.bat stress full [HEX-SEED]
echo   run-debug.bat benchmark
echo   run-debug.bat benchmark full
echo   run-debug.bat list
exit /b 2

:run_pattern_tests
call :run_noargs "TestPatternSearch.exe" || exit /b 1
call :run_noargs "TestPatternSearchRandom.exe" || exit /b 1
call :run_dunitx || exit /b 1
call :run_stress_quick || exit /b 1
echo.
echo Alle Pattern-Tests erfolgreich.
exit /b 0

:run_dunitx
if not exist "%BIN%\PatternSearchDUnitX.exe" (
  echo FEHLT: %BIN%\PatternSearchDUnitX.exe
  exit /b 2
)
set "NATIVEPE_DUNITX_XML=%RESULTS%\PatternSearchDUnitX-Debug.xml"
echo.
echo ^> PatternSearchDUnitX.exe
echo   XML: %NATIVEPE_DUNITX_XML%
"%BIN%\PatternSearchDUnitX.exe"
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%
exit /b %RC%

:run_stress_quick
if not exist "%BIN%\TestPatternSearchStress.exe" (
  echo FEHLT: %BIN%\TestPatternSearchStress.exe
  exit /b 2
)
echo.
echo ^> TestPatternSearchStress.exe
"%BIN%\TestPatternSearchStress.exe"
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%
exit /b %RC%

:run_stress_full_prompt
set "SEED="
set /p "SEED=Optionaler HEX-Seed ^(leer = Standardseed^): "
set "SEEDARG="
if not "%SEED%"=="" set "SEEDARG=--seed=%SEED%"
call :run_stress_full
exit /b %ERRORLEVEL%

:run_stress_full
if not exist "%BIN%\TestPatternSearchStress.exe" (
  echo FEHLT: %BIN%\TestPatternSearchStress.exe
  exit /b 2
)
echo.
echo ^> TestPatternSearchStress.exe --full %SEEDARG%
"%BIN%\TestPatternSearchStress.exe" --full %SEEDARG%
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%
exit /b %RC%

:run_benchmark_quick
if not exist "%BIN%\PatternSearchBenchmark.exe" (
  echo FEHLT: %BIN%\PatternSearchBenchmark.exe
  exit /b 2
)
set "CSV=%RESULTS%\pattern-benchmark-Debug-quick.csv"
echo.
echo ^> PatternSearchBenchmark.exe --csv="%CSV%"
"%BIN%\PatternSearchBenchmark.exe" --csv="%CSV%"
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%
echo CSV: %CSV%
exit /b %RC%

:run_benchmark_full
if not exist "%BIN%\PatternSearchBenchmark.exe" (
  echo FEHLT: %BIN%\PatternSearchBenchmark.exe
  exit /b 2
)
set "CSV=%RESULTS%\pattern-benchmark-Debug-full.csv"
echo.
echo ^> PatternSearchBenchmark.exe --full --csv="%CSV%"
"%BIN%\PatternSearchBenchmark.exe" --full --csv="%CSV%"
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%
echo CSV: %CSV%
exit /b %RC%

:run_custom_prompt
set "CUSTOMEXE="
set /p "CUSTOMEXE=EXE-Name ^(z.B. TestPatternSearch.exe^): "
if "%CUSTOMEXE%"=="" exit /b 2
set "CUSTOMARGS="
set /p "CUSTOMARGS=Argumente ^(optional^): "
if "%CUSTOMARGS%"=="" (
  call :run_noargs "%CUSTOMEXE%"
) else (
  if not exist "%BIN%\%CUSTOMEXE%" (
    echo EXE nicht gefunden:
    echo   %BIN%\%CUSTOMEXE%
    exit /b 2
  )
  echo.
  echo ^> %CUSTOMEXE% %CUSTOMARGS%
  "%BIN%\%CUSTOMEXE%" %CUSTOMARGS%
)
exit /b %ERRORLEVEL%

:run_noargs
if not exist "%BIN%\%~1" (
  echo FEHLT: %BIN%\%~1
  exit /b 2
)
echo.
echo ^> %~1
"%BIN%\%~1"
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%
exit /b %RC%

:list_exes
echo.
echo EXEs in %BIN%:
echo.
dir /b /a-d "%BIN%\*.exe" 2^>nul
exit /b 0
