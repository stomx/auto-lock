// 사이트 카피·자산을 한 곳에 모은 데이터 모듈. 컴포넌트는 표현만 담당하고
// 내용은 여기서 가져와, 문구 수정 시 컴포넌트를 건드릴 필요가 없다.

export const REPO = 'https://github.com/stomx/auto-lock'

// 버전 단일 출처: 루트 CHANGELOG.md 최상단 릴리스. vite.config.js가 빌드 타임에
// __APP_VERSION__('0.5.2' 등)으로 주입한다. 같은 값이 index.html JSON-LD에도 주입됨.
export const LATEST_VERSION = `v${__APP_VERSION__}` // 예: 'v0.5.2'

export const RELEASES_URL = `${REPO}/releases/latest`
export const INSTALL_URL = `${REPO}/blob/main/INSTALL.md`

// 변경 이력 원문(main 브랜치 CHANGELOG.md). 사람이 보는 GitHub 링크와,
// 브라우저에서 직접 받아 렌더하는 raw 링크. raw는 CORS 허용(*)·5분 캐시.
export const CHANGELOG_URL = `${REPO}/blob/main/CHANGELOG.md`
export const CHANGELOG_RAW_URL = 'https://raw.githubusercontent.com/stomx/auto-lock/main/CHANGELOG.md'

// 다운로드 폴백 = releases/latest(최신 릴리스 페이지, 항상 살아있음).
// 직접 .dmg 링크(releases/latest/download/AutoLock-<버전>-arm64.dmg)는 자산
// 파일명에 버전이 박혀 있어, 새 릴리스가 나오고 사이트 재배포 전이면 파일명이
// 어긋나 404가 된다(최초 버그의 원인). 그래서 폴백은 릴리스 페이지로 두고,
// JS가 동작하는 방문자는 useLatestDmg가 실제 .dmg URL로 교체한다.
export const DOWNLOAD_DMG = RELEASES_URL

export const HERO = {
  title: '자리를 비우면, Mac이 알아서 잠깁니다',
  tagline:
    '폰·워치의 블루투스 신호로 거리를 읽어 자동으로 화면을 잠그는 macOS 메뉴바 앱. 다시 다가오면 깨어납니다.',
  sub: 'Apple Silicon · macOS 13+ · 오픈소스',
}

// asset() 으로 base 경로를 붙여 dev/배포 모두에서 동작하게 한다.
// settings.png는 menubar-popover에 설정 영역이 그대로 포함돼 중복이라 제외.
export const SCREENSHOTS = [
  { src: 'images/menubar-popover.png', caption: '메뉴바 팝오버 — 근접 상태·신호 강도·설정' },
  { src: 'images/device-picker.png', caption: '디바이스 선택 — 신호 강도순 라이브' },
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
