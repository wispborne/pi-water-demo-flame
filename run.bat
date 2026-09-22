@echo off
rem Run 30 Floors & a Pool. Builds the Windows release first if needed.
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

if not exist "%EXE%" (
  echo Building the Windows release, first run only.
  pushd app
  flutter build windows --release
  popd
  if errorlevel 1 (
    echo Build failed.
    pause
    exit /b 1
  )
)

start "" "%EXE%"
endlocal
