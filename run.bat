@echo off
rem Run 30 Floors & a Pool. Builds the Windows release if the app is missing
rem or older than the source, then runs it.
setlocal
cd /d "%~dp0"

set "EXE=app\build\windows\x64\runner\Release\water_tower_app.exe"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter not found on PATH.
  echo Install the Flutter SDK, then rerun.
  pause
  exit /b 1
)

set "NEED=1"
if exist "%EXE%" goto check
goto build

:check
rem Rebuild if the exe is older than any file under app\ (build output excluded).
for /f "usebackq" %%i in (`powershell -NoProfile -Command "$s = Get-ChildItem app -Recurse -File | Where-Object { $_.FullName -notlike '*\build\*' -and $_.FullName -notlike '*\.dart_tool\*' }; $m = ($s | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime; if ((Get-Item '%EXE%').LastWriteTime -gt $m) { '0' } else { '1' }"`) do set "NEED=%%i"
if "%NEED%"=="0" goto run

:build
echo Building the Windows release.
pushd app
call flutter build windows --release
popd
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)

:run
start "" "%EXE%"
endlocal
