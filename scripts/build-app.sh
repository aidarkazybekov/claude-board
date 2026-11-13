#!/bin/zsh
# Builds ClaudeBoard.app and installs it to ~/Applications.
# Usage: scripts/build-app.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/ClaudeBoard.app
VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")

echo "› swift build (release)"
swift build -c release

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeBoard "$APP/Contents/MacOS/ClaudeBoard"
cp Resources/plotly-cartesian.min.js "$APP/Contents/Resources/"

# Icon (cached; delete build/AppIcon.icns to regenerate)
if [[ ! -f build/AppIcon.icns ]]; then
  echo "› rendering icon"
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make-icon.swift build/icon-1024.png >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeBoard</string>
  <key>CFBundleDisplayName</key><string>ClaudeBoard</string>
  <key>CFBundleIdentifier</key><string>io.github.aidarkazybekov.claudeboard</string>
  <key>CFBundleExecutable</key><string>ClaudeBoard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (ad-hoc codesign skipped)"

if [[ "${1:-}" != "--no-install" ]]; then
  mkdir -p "$HOME/Applications"
  # Quit a running copy so the new build is picked up.
  pkill -x ClaudeBoard 2>/dev/null && sleep 1 || true
  rm -rf "$HOME/Applications/ClaudeBoard.app"
  cp -R "$APP" "$HOME/Applications/ClaudeBoard.app"
  echo "✓ installed ~/Applications/ClaudeBoard.app"
else
  echo "✓ built $APP"
fi
