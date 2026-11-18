#!/usr/bin/env bash
# Builds Portside.app from source.
#   ./build.sh            build into ./build/Portside.app
#   ./build.sh --install  build, copy to /Applications and launch
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Portside"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift not found. Install Xcode or run: xcode-select --install"
  exit 1
fi

echo "› Compiling (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.png ]; then
  echo "› Building icon"
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "› Signing (ad hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Built $APP"

if [ "${1:-}" = "--install" ]; then
  echo "› Installing to /Applications"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
  echo "✓ Portside is running. Look for the sailboat in your menu bar."
else
  echo "  Run it with: open $APP"
  echo "  Or install with: ./build.sh --install"
fi
