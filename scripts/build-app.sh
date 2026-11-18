#!/bin/zsh
# Builds Pitwall.app and installs it to ~/Applications.
# Usage: scripts/build-app.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Pitwall.app
VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")

echo "› swift build (release)"
swift build -c release

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Pitwall "$APP/Contents/MacOS/Pitwall"
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
  <key>CFBundleName</key><string>Pitwall</string>
  <key>CFBundleDisplayName</key><string>Pitwall</string>
  <key>CFBundleIdentifier</key><string>io.github.aidarkazybekov.pitwall</string>
  <key>CFBundleExecutable</key><string>Pitwall</string>
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
  # Quit a running copy so the new build is picked up (ClaudeBoard is the app's old name).
  pkill -x Pitwall 2>/dev/null && sleep 1 || true
  pkill -x ClaudeBoard 2>/dev/null && sleep 1 || true
  rm -rf "$HOME/Applications/Pitwall.app"
  cp -R "$APP" "$HOME/Applications/Pitwall.app"
  echo "✓ installed ~/Applications/Pitwall.app"
  if [[ -d "$HOME/Applications/ClaudeBoard.app" ]]; then
    rm -rf "$HOME/Applications/ClaudeBoard.app"
    echo "✓ removed ~/Applications/ClaudeBoard.app (Pitwall copies its settings and data on first launch)"
  fi
else
  echo "✓ built $APP"
fi
