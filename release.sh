#!/usr/bin/env bash
# Build a redistributable AutoLock.app + DMG + ZIP for arm64 macOS.
#
# Output: dist/AutoLock-<version>-arm64.dmg, dist/AutoLock-<version>-arm64.zip
# plus SHA256 checksums.
#
# Codesigning: ad-hoc (no Apple Developer account). Recipients must allow
# the app on first launch — see INSTALL.md.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="AutoLock"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ARCH="arm64"

DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCH.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCH.zip"

echo "▶ Cleaning $DIST_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "▶ swift build -c release --arch arm64"
swift build -c release --arch arm64

BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "▶ Assembling $APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "▶ Stripping debug symbols"
strip -x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "▶ Ad-hoc codesigning"
# --options runtime turns on hardened runtime, which is required for
# SMAppService registration to be honored on a clean machine.
codesign --force --deep --sign - --options runtime --timestamp=none "$APP_DIR"

echo "▶ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "▶ Building DMG"
DMG_STAGE="$DIST_DIR/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGE"

echo "▶ Building ZIP"
( cd "$DIST_DIR" && /usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$(basename "$ZIP_PATH")" )

echo "▶ Computing checksums"
( cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > "SHA256SUMS.txt" )

echo
echo "✅ Release artifacts:"
ls -lh "$DMG_PATH" "$ZIP_PATH" "$DIST_DIR/SHA256SUMS.txt"
echo
echo "Distribute alongside INSTALL.md so coworkers know how to bypass Gatekeeper."
