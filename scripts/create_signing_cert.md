# AutoLock 코드서명 인증서 가이드

AutoLock은 v0.5.0부터 **self-signed 코드서명**을 쓴다. 자동 업데이트(자가교체)
후에도 접근성·블루투스 권한이 유지되게 하기 위함이다.

## 왜 self-signed인가

ad-hoc 서명(`codesign --sign -`)은 바이너리가 바뀔 때마다 코드 해시(cdhash)가
변한다. macOS의 권한 시스템(TCC)은 designated requirement가 cdhash로 묶인
ad-hoc 앱을, 업데이트되면 **다른 앱으로 인식**해 권한을 리셋한다.

고정된 self-signed 인증서로 서명하면 DR이 다음 형태가 된다:

```
identifier "com.local.autolock" and certificate leaf = H"<인증서 해시>"
```

bundle id와 인증서 leaf만 같으면 버전이 바뀌어 cdhash가 달라져도 **동일 앱**으로
인식 → 권한 유지. 따라서 **모든 빌드가 같은 인증서**로 서명되어야 한다.

## 방법 A — 자동 (권장)

```bash
./scripts/create_signing_cert.sh
```

openssl로 codeSigning 인증서를 만들고 `.p12`로 묶어 login keychain에 import한다.
`.p12` 비밀번호와 로그인 암호를 물어본다.

> **⚠️ `.p12`를 반드시 백업하라** (1Password 등). 빌드 머신이 바뀌면 같은 `.p12`를
> import해야 leaf가 동일해 권한이 유지된다. 분실하면 다음 업데이트 때 전 사용자가
> 권한을 1회 다시 줘야 한다.

import는 이렇게 한다:

```bash
security import autolock-signing.p12 -k ~/Library/Keychains/login.keychain-db \
  -P <p12암호> -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k <로그인암호> ~/Library/Keychains/login.keychain-db
```

## 방법 B — 수동 (방법 A가 codesign에 거부될 때)

드물게 openssl 인증서를 `codesign`이 거부하면(`errSecInternalComponent`,
"no identity found") Keychain Access로 만든다:

1. **Keychain Access** 실행
2. 메뉴 → **Certificate Assistant** → **Create a Certificate…**
3. 설정:
   - **Name**: `AutoLock Self-Signed`
   - **Identity Type**: *Self Signed Root*
   - **Certificate Type**: **Code Signing**
4. 생성 후 **login** 키체인에 저장(개인키 포함).
5. 확인:
   ```bash
   security find-identity -p codesigning
   ```
   목록에 `AutoLock Self-Signed`가 보이면 성공.

   > `-v`(valid-only)는 쓰지 마세요. self-signed 인증서는 신뢰 체인이 없어
   > `CSSMERR_TP_NOT_TRUSTED`로 표시되며 `-v`에는 **0개로 나옵니다**. 코드서명
   > 자체는 정상 동작하므로 `-v` 없이 확인해야 합니다(release.sh도 `-v` 없이 검사).

## 빌드 시 사용

`release.sh`는 인증서가 있으면 자동으로 그걸로 서명하고, **없으면 빌드를 중단**한다
(ad-hoc 릴리스가 나가면 전 사용자 권한이 리셋되므로). 서명 후 DR이 `certificate leaf`
형태인지 검증한다.

```bash
./release.sh
codesign -d -r- dist/AutoLock.app   # designated => ... certificate leaf = H"..." 확인
```

다른 식별자 이름을 쓰려면 환경변수로:

```bash
AUTOLOCK_SIGN_IDENTITY="내 인증서 이름" ./release.sh
```
