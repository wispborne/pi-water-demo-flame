#!/bin/sh
# Run 30 Floors & a Pool. Builds the macOS release first if needed.
set -e
cd "$(dirname "$0")"

APP="app/build/macos/Build/Products/Release/water_tower_app.app"

command -v flutter > /dev/null 2>&1 || {
  echo "Flutter not found on PATH."
  echo "Install the Flutter SDK, then rerun."
  exit 1
}

echo "Building the macOS release."
(cd app && flutter build macos --release)

open "$APP"
