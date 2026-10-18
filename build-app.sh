#!/bin/sh
# Builds Lorito.app with SwiftPM (no Xcode project needed). Output: build/Lorito.app
# `./build-app.sh install` also copies it to /Applications and launches that copy.
set -eu
cd "$(dirname "$0")"
swift build -c release --quiet

APP=build/Lorito.app
pkill -x Lorito 2>/dev/null || true   # a running app whose bundle is replaced fails TCC validation
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lorito "$APP/Contents/MacOS/"

# The icon is drawn by the app itself (`--icon`), so it cannot drift from the menu bar glyph.
T=$(mktemp -d) && mkdir "$T/AppIcon.iconset"
.build/release/Lorito --icon "$T/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$T/icon.png" --out "$T/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$T/icon.png" --out "$T/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$T/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$T"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>nl.joris.lorito</string>
  <key>CFBundleName</key><string>Lorito</string>
  <key>CFBundleExecutable</key><string>Lorito</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Lorito records your voice while you dictate and transcribes it on this Mac.</string>
</dict></plist>
PLIST

# Sign with "Lorito Dev" (see make-signing-cert.sh) so Accessibility grants survive rebuilds; ad-hoc otherwise.
if [ -z "${CODESIGN_IDENTITY:-}" ]; then
  if security find-identity -v -p codesigning | grep -q "Lorito Dev"; then CODESIGN_IDENTITY="Lorito Dev"; else CODESIGN_IDENTITY="-"; fi
fi
codesign --force --deep -s "$CODESIGN_IDENTITY" "$APP"
echo "signed with: $CODESIGN_IDENTITY"
codesign --verify --deep --strict "$APP" && echo "built $APP"
if [ "${1:-}" = install ]; then
  rm -rf /Applications/Lorito.app && cp -c -R "$APP" /Applications/ && APP=/Applications/Lorito.app && echo "installed $APP"
fi
open "$APP"
