#!/bin/zsh
# Build Tabview.app and install it to ~/Applications.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Tabview.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Tabview "$APP/Contents/MacOS/Tabview"
cp Info.plist "$APP/Contents/Info.plist"
# Stable identifier so macOS remembers the Accessibility / Automation grants between builds.
codesign --force --sign - --identifier com.nanaamoako.tabview "$APP"
mkdir -p ~/Applications
pkill -x Tabview 2>/dev/null || true
rm -rf ~/Applications/Tabview.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/Tabview.app"
