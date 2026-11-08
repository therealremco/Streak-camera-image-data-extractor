#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
bin_path="$(swift build -c release --show-bin-path)"
app="dist/StreakExtractor.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/StreakExtractor" "$app/Contents/MacOS/StreakExtractor"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
