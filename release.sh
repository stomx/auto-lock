#!/usr/bin/env bash
# Build a redistributable AutoLock.app + DMG + ZIP for arm64 macOS.
#
# Output: dist/AutoLock-<version>-arm64.dmg, dist/AutoLock-<version>-arm64.zip
# plus SHA256 checksums.
#
# Codesigning: fixed self-signed identity (no Apple Developer account).
# Recipients must allow the app on first launch — see INSTALL.md.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="AutoLock"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ARCH="arm64"
PINNED_CERT_LEAF_FILE="$ROOT/scripts/release-cert-leaf.txt"

DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCH.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCH.zip"

echo "▶ Running meaningful 100% coverage gate"
"$ROOT/scripts/coverage.sh"

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

# Self-signed codesigning. A FIXED self-signed cert keeps the designated
# requirement bound to the certificate leaf (not the cdhash), so updated builds
# are recognized as the same app and TCC permissions (Accessibility/Bluetooth)
# survive auto-updates. See scripts/create_signing_cert.md.
#
# release MUST NOT fall back to ad-hoc: an ad-hoc release would reset every
# user's permissions on their next update. So we hard-fail if the cert is absent.
SIGN_ID="${AUTOLOCK_SIGN_IDENTITY:-AutoLock Self-Signed}"
if ! security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "❌ 코드서명 인증서 '$SIGN_ID' 가 keychain에 없습니다." >&2
    echo "   self-signed 빌드는 권한 유지를 위해 고정 인증서가 필요합니다." >&2
    echo "   → ./scripts/create_signing_cert.sh 로 생성하거나 백업 .p12를 import 하세요." >&2
    exit 1
fi

echo "▶ Codesigning with '$SIGN_ID'"
# --options runtime turns on hardened runtime, which is required for
# SMAppService registration to be honored on a clean machine.
codesign --force --deep --sign "$SIGN_ID" --options runtime --timestamp=none "$APP_DIR"

echo "▶ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "▶ Verifying designated requirement is certificate-leaf-bound (not cdhash)"
# A cdhash-bound DR means we accidentally signed ad-hoc → permissions would
# reset on update. Require the cert-leaf form before shipping.
if ! codesign -d -r- "$APP_DIR" 2>&1 | grep -q "certificate leaf"; then
    echo "❌ designated requirement가 certificate leaf 기반이 아닙니다(ad-hoc 의심)." >&2
    codesign -d -r- "$APP_DIR" 2>&1 | sed -n 's/^/   /p' >&2
    exit 1
fi

if [[ ! -f "$PINNED_CERT_LEAF_FILE" ]]; then
    echo "❌ 서명 인증서 leaf 고정 파일이 없습니다: $PINNED_CERT_LEAF_FILE" >&2
    exit 1
fi
EXPECTED_LEAF="$(tr '[:upper:]' '[:lower:]' < "$PINNED_CERT_LEAF_FILE" | tr -d '[:space:]')"
ACTUAL_LEAF="$(codesign -d -r- "$APP_DIR" 2>&1 \
    | sed -n 's/.*certificate leaf = H"\([0-9A-Fa-f]*\)".*/\1/p' \
    | tr '[:upper:]' '[:lower:]')"
if [[ ! "$EXPECTED_LEAF" =~ ^[0-9a-f]{40}$ ]] || [[ "$ACTUAL_LEAF" != "$EXPECTED_LEAF" ]]; then
    echo "❌ 코드서명 인증서 leaf가 고정값과 다릅니다." >&2
    echo "   expected: $EXPECTED_LEAF" >&2
    echo "   actual:   ${ACTUAL_LEAF:-<missing>}" >&2
    echo "   백업된 AutoLock 서명 .p12를 import한 뒤 다시 시도하세요." >&2
    exit 1
fi
echo "✅ Pinned certificate leaf verified: $ACTUAL_LEAF"

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
