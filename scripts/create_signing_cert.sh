#!/usr/bin/env bash
# AutoLock self-signed 코드서명 인증서 생성 + login keychain import.
#
# 왜 필요한가: ad-hoc 서명(codesign --sign -)은 빌드마다 cdhash가 바뀌어
# macOS TCC가 업데이트된 앱을 "다른 앱"으로 보고 접근성·블루투스 권한을
# 리셋한다. 고정된 self-signed 인증서로 서명하면 designated requirement가
# `identifier "<bundle id>" and certificate leaf = H"..."` 형태가 되어,
# 버전이 바뀌어도 동일 앱으로 인식 → 권한이 유지된다.
#
# ⚠️ 재현성 핵심: 생성된 .p12 를 안전한 곳(1Password 등)에 백업하라.
#   - 빌드 머신이 바뀌면 같은 .p12 를 import 해야 leaf가 동일 → 권한 유지.
#   - .p12 분실 = 모든 사용자가 다음 업데이트 때 권한을 1회 다시 줘야 함.
#
# codesign이 이 인증서를 거부하면(드물게 errSecInternalComponent 등)
# scripts/create_signing_cert.md 의 Keychain Access 수동 절차로 대체하라.

set -euo pipefail

CERT_NAME="${AUTOLOCK_SIGN_IDENTITY:-AutoLock Self-Signed}"
OUT_DIR="${1:-$HOME/.autolock-signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
PINNED_LEAF_FILE="$(cd "$(dirname "$0")" && pwd)/release-cert-leaf.txt"

verify_pinned_leaf() {
    if [ ! -f "$PINNED_LEAF_FILE" ]; then
        echo "❌ 인증서 leaf 고정 파일이 없습니다: $PINNED_LEAF_FILE" >&2
        return 1
    fi
    expected="$(tr '[:upper:]' '[:lower:]' < "$PINNED_LEAF_FILE" | tr -d '[:space:]')"
    actual="$(security find-certificate -c "$CERT_NAME" -Z "$KEYCHAIN" 2>/dev/null \
        | sed -n 's/^SHA-1 hash: //p' | head -n 1 | tr '[:upper:]' '[:lower:]')"
    if [ "$actual" != "$expected" ]; then
        echo "❌ '$CERT_NAME' 인증서 leaf가 릴리스 고정값과 다릅니다." >&2
        echo "   expected: $expected" >&2
        echo "   actual:   ${actual:-<missing>}" >&2
        echo "   새 인증서를 사용하지 말고 백업된 AutoLock 서명 .p12를 import하세요." >&2
        return 1
    fi
}

mkdir -p "$OUT_DIR"
KEY="$OUT_DIR/autolock-signing.key"
CRT="$OUT_DIR/autolock-signing.crt"
P12="$OUT_DIR/autolock-signing.p12"

if security find-identity -p codesigning | grep -q "$CERT_NAME"; then
    verify_pinned_leaf
    echo "✅ 이미 '$CERT_NAME' 인증서가 keychain에 있습니다. (재생성하려면 먼저 제거)"
    security find-identity -p codesigning | grep "$CERT_NAME"
    exit 0
fi

if [ -f "$PINNED_LEAF_FILE" ] && [ "${AUTOLOCK_ALLOW_CERT_ROTATION:-0}" != "1" ]; then
    echo "❌ 릴리스 인증서 leaf가 이미 고정되어 있어 새 인증서를 만들 수 없습니다." >&2
    echo "   백업된 AutoLock 서명 .p12를 login keychain에 import하세요." >&2
    echo "   의도적인 인증서 교체라면 AUTOLOCK_ALLOW_CERT_ROTATION=1로 실행한 뒤" >&2
    echo "   release-cert-leaf.txt 변경을 별도로 검토해야 합니다." >&2
    exit 1
fi

echo "▶ .p12 비밀번호를 입력하세요(백업용 — 잊지 마세요):"
read -r -s P12_PW
echo
echo "▶ login keychain 비밀번호(보통 macOS 로그인 암호):"
read -r -s KC_PW
echo

echo "▶ self-signed 코드서명 인증서 생성 (openssl, 10년 유효)"
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$KEY" -out "$CRT" \
    -subj "/CN=$CERT_NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"

echo "▶ PKCS#12(.p12)로 묶기"
openssl pkcs12 -export -inkey "$KEY" -in "$CRT" \
    -name "$CERT_NAME" -out "$P12" -passout "pass:$P12_PW"

echo "▶ login keychain에 import (codesign이 쓸 수 있도록)"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PW" -T /usr/bin/codesign

echo "▶ codesign이 프롬프트 없이 키를 쓰도록 partition-list 설정"
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$KC_PW" "$KEYCHAIN" >/dev/null

echo
if security find-identity -p codesigning | grep -q "$CERT_NAME"; then
    verify_pinned_leaf
    echo "✅ 완료. codesign 인증서 등록됨:"
    security find-identity -p codesigning | grep "$CERT_NAME"
    echo
    echo "🔐 백업: $P12  (1Password 등에 안전 보관 후 OUT_DIR 정리 권장)"
    echo "   다음: ./release.sh 로 빌드하면 이 인증서로 서명됩니다."
else
    echo "❌ 인증서가 codesigning identity로 등록되지 않았습니다."
    echo "   scripts/create_signing_cert.md 의 Keychain Access 수동 절차를 사용하세요."
    exit 1
fi
