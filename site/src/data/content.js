// 사이트 카피·자산을 한 곳에 모은 데이터 모듈. 컴포넌트는 표현만 담당하고
// 내용은 여기서 가져와, 문구 수정 시 컴포넌트를 건드릴 필요가 없다.

export const REPO = 'https://github.com/stomx/auto-lock'
export const LATEST_VERSION = 'v0.5.1'
// releases/latest/download/... 는 버전이 올라가도 항상 최신을 가리킨다.
export const DOWNLOAD_DMG = `${REPO}/releases/latest/download/AutoLock-0.5.1-arm64.dmg`
export const RELEASES_URL = `${REPO}/releases/latest`
export const INSTALL_URL = `${REPO}/blob/main/INSTALL.md`

export const HERO = {
  title: '자리를 비우면, Mac이 알아서 잠깁니다',
  tagline:
    '폰·워치의 블루투스 신호로 거리를 읽어 자동으로 화면을 잠그는 macOS 메뉴바 앱. 다시 다가오면 깨어납니다.',
  sub: 'Apple Silicon · macOS 13+ · 오픈소스',
}

// asset() 으로 base 경로를 붙여 dev/배포 모두에서 동작하게 한다.
export const SCREENSHOTS = [
  { src: 'images/menubar-popover.png', caption: '메뉴바 팝오버 — 근접 상태·신호 강도' },
  { src: 'images/device-picker.png', caption: '디바이스 선택 — 신호 강도순 라이브' },
  { src: 'images/settings.png', caption: '설정 — 토글과 거리 임계값' },
]

// icon 값은 components/Icons.jsx 의 ICONS 키.
export const FEATURES = [
  {
    icon: 'lock',
    title: '근접 기반 자동 잠금',
    body: '등록한 폰·워치가 멀어져 신호가 약해지면 카운트다운 후 화면을 잠급니다. 잠깐의 신호 끊김에는 잠그지 않습니다.',
  },
  {
    icon: 'wake',
    title: '근접 시 화면 깨우기',
    body: '다시 다가가면 화면이 미리 켜져, Touch ID나 Apple Watch로 한 번에 풀 수 있습니다.',
  },
  {
    icon: 'unlock',
    title: '자동 잠금 해제 (실험적)',
    body: 'Keychain에 저장한 로그인 암호를 근접 복귀 시 자동 입력. 환경에 따라 화면 깨우기까지만 동작할 수 있습니다.',
  },
  {
    icon: 'update',
    title: '완전 자동 업데이트',
    body: '"업데이트" 버튼 한 번으로 다운로드·검증·교체·재실행까지. 업데이트해도 권한을 다시 설정할 필요가 없습니다.',
  },
  {
    icon: 'shield',
    title: '로컬에서만 동작',
    body: '모든 처리는 Mac 안에서 끝납니다. 암호는 macOS Keychain에 저장되고 외부로 전송되지 않습니다.',
  },
  {
    icon: 'menubar',
    title: '가벼운 메뉴바 앱',
    body: 'Dock 아이콘 없이 메뉴바에 상주. 한 번에 한 기기를 추적하며 거리 임계값을 직접 조절합니다.',
  },
]

export const STEPS = [
  'CoreBluetooth로 주변 BLE 신호를 스캔하고, 등록한 디바이스의 **RSSI(신호 강도)를 이동평균으로 평활화**합니다.',
  '신호가 임계값보다 약해지거나 **15초 동안 안 잡히면** 카운트다운을 시작합니다.',
  '카운트다운 마지막 5초에는 **화면 중앙에 큰 숫자 오버레이**가 떠 잠금이 임박했음을 알립니다.',
  '카운트다운이 끝나면 **화면을 잠급니다.** 신호가 급락하면 즉시 잠급니다.',
  '다시 가까워지면 화면을 깨우고, 설정에 따라 **암호를 자동 입력해 풀 수도** 있습니다.',
]
