#!/bin/bash
# Builds Exhibit Maker.app, installs (or updates) it in /Applications, and launches it.
# Requires Apple's Command Line Tools (run `xcode-select --install` once if needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="Exhibit Maker.app"
EXEC="ExhibitMaker"

echo "Building…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARCH="$(uname -m)"
swiftc -O -swift-version 5 -target "${ARCH}-apple-macos13.0" \
  main.swift Model.swift Renderer.swift ContentView.swift \
  -o "$APP/Contents/MacOS/$EXEC" \
  -framework Cocoa -framework SwiftUI -framework PDFKit -framework UniformTypeIdentifiers
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/"
# Exhibit Maker needs no special permissions, so a simple local signature is enough.
codesign --force --sign - "$APP"

echo "Installing to /Applications…"
pkill -x "$EXEC" 2>/dev/null && sleep 0.5 || true
rm -rf "/Applications/$APP"
ditto "$APP" "/Applications/$APP"
xattr -cr "/Applications/$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP"

open "/Applications/$APP" || {
  echo "Finder launch failed; starting the app directly instead."
  nohup "/Applications/$APP/Contents/MacOS/$EXEC" >/dev/null 2>&1 &
}
echo "Done. Exhibit Maker is in your Applications folder."
