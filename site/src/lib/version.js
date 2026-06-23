// CHANGELOG.md(단일 출처)의 최상단 릴리스에서 버전·날짜를 뽑아낸다.
// 버전 문자열이 content.js·index.html·다운로드 링크에 흩어지지 않도록,
// 모든 버전 표기는 여기 한 곳을 거쳐 파생된다.

// "## [0.5.2] — 2026-06-22" 형태의 첫 헤더를 찾는다.
const RELEASE_RE = /^##\s*\[([^\]]+)\]\s*(?:—|-)?\s*(.*)$/m

// 반환: { version: '0.5.2', tag: 'v0.5.2', date: '2026-06-22' }
// 파싱 실패 시 fallback 으로 안전하게 떨어진다(빌드를 막지 않음).
export function latestRelease(changelogMarkdown, fallback = '0.0.0') {
  const m = changelogMarkdown.match(RELEASE_RE)
  const version = m ? m[1].trim() : fallback
  const date = m ? m[2].trim() : ''
  return { version, tag: `v${version}`, date }
}
