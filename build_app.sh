#!/usr/bin/env bash
# Build a self-contained AutoLock.app bundle from the SPM target.
#
# Why a custom script: SwiftPM emits a plain Mach-O executable. macOS only
# loads Info.plist (and surfaces the Bluetooth usage prompt) for proper .app
# bundles, so we wrap the binary by hand.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="AutoLock"
APP_DIR="$ROOT/build/$APP_NAME.app"

echo "▶ swift build (-c $CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "Built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "▶ Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Dev build: prefer the self-signed cert (so permission behavior matches a
# release), but fall back to ad-hoc when it's absent — local dev doesn't need
# permission persistence. (release.sh hard-fails instead; see its comment.)
SIGN_ID="${AUTOLOCK_SIGN_IDENTITY:-AutoLock Self-Signed}"
if security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "▶ Codesign with '$SIGN_ID'"
    codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
else
    echo "⚠️ 인증서 '$SIGN_ID' 없음 — ad-hoc 서명(개발용). 자가교체 권한유지 테스트엔 부적합."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo
echo "✅ Built: $APP_DIR"
echo "   Run: open \"$APP_DIR\""
echo "   First launch will request Bluetooth permission."
