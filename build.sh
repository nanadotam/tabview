#!/bin/zsh
# Build Tabview.app.
#   ./build.sh            build for this Mac and install to ~/Applications
#   ./build.sh --release  universal (Apple silicon + Intel) build, zipped into build/ for GitHub Releases
set -e
cd "$(dirname "$0")"

if [[ "$1" == "--release" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Tabview"
    # Ad-hoc: anyone can run it, no developer certificate needed.
    IDENTITY="-"
else
    swift build -c release
    BIN=.build/release/Tabview
    # Prefer a real certificate locally so macOS remembers the Accessibility grant across rebuilds.
    IDENTITY=$(security find-identity -p codesigning -v | awk -F'"' '/Apple Development|Developer ID/ {print $2; exit}')
    IDENTITY=${IDENTITY:--}
fi

APP=build/Tabview.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tabview"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f Assets/AppIcon.icns ]] && cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "$IDENTITY" --identifier com.nanaamoako.tabview "$APP"

if [[ "$1" == "--release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
    (cd build && rm -f Tabview-*.zip(N) && ditto -c -k --keepParent Tabview.app "Tabview-$VERSION.zip")
    echo "Built build/Tabview-$VERSION.zip"
else
    pkill -x Tabview 2>/dev/null || true
    rm -rf ~/Applications/Tabview.app
    cp -R "$APP" ~/Applications/
    echo "Installed ~/Applications/Tabview.app (signed: $IDENTITY)"
fi
