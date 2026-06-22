// Keep a Changelog 형식의 마크다운을 구조화된 릴리스 배열로 파싱한다.
// 단일 소스: repo 루트 CHANGELOG.md (빌드 시 src/data로 동기화).
//
// 반환 형태:
//   [{ version, date, sections: [{ title, items: [string, ...] }] }, ...]
//
// 인라인 마크다운(**bold**, `code`)은 별도 렌더러(parseInline)에서 처리하므로
// 여기서는 원문 문자열을 그대로 보존한다.

const VERSION_RE = /^##\s*\[([^\]]+)\]\s*(?:—|-)?\s*(.*)$/
const SECTION_RE = /^###\s+(.*)$/
const BULLET_RE = /^\s*[-*]\s+(.*)$/

export function parseChangelog(markdown) {
  const lines = markdown.split('\n')
  const releases = []
  let release = null
  let section = null

  const pushItemContinuation = (text) => {
    // 들여쓰기된 후속 줄은 직전 항목에 이어붙인다(원문 줄바꿈은 공백으로).
    if (section && section.items.length > 0) {
      section.items[section.items.length - 1] += ' ' + text.trim()
    }
  }

  for (const raw of lines) {
    const versionMatch = raw.match(VERSION_RE)
    if (versionMatch) {
      release = { version: versionMatch[1].trim(), date: versionMatch[2].trim(), sections: [] }
      releases.push(release)
      section = null
      continue
    }
    if (!release) continue // 헤더(제목/설명) 영역은 건너뛴다

    const sectionMatch = raw.match(SECTION_RE)
    if (sectionMatch) {
      section = { title: sectionMatch[1].trim(), items: [] }
      release.sections.push(section)
      continue
    }

    const bulletMatch = raw.match(BULLET_RE)
    if (bulletMatch) {
      // 섹션 헤더 없이 곧장 불릿이 오면 무제목 섹션을 만든다.
      if (!section) {
        section = { title: '', items: [] }
        release.sections.push(section)
      }
      // 들여쓴 하위 불릿(예: "  - ...")은 이어붙인다.
      const indented = /^\s{2,}[-*]\s+/.test(raw)
      if (indented) pushItemContinuation('— ' + bulletMatch[1])
      else section.items.push(bulletMatch[1].trim())
      continue
    }

    const trimmed = raw.trim()
    if (trimmed === '') continue

    // 불릿이 아닌 본문 줄: 섹션 안이면 직전 항목 이어쓰기, 아니면 무제목 섹션의
    // 산문 문단으로 취급(예: 0.3.1의 도입 설명).
    if (section && section.items.length > 0) {
      pushItemContinuation(trimmed)
    } else {
      if (!section) {
        section = { title: '', items: [] }
        release.sections.push(section)
      }
      section.items.push(trimmed)
    }
  }

  return releases
}

// 섹션 제목(영문 Keep-a-Changelog 키워드)을 한국어 라벨과 색조로 매핑.
const SECTION_META = {
  Added: { label: '추가', tone: 'add' },
  Changed: { label: '변경', tone: 'change' },
  Fixed: { label: '수정', tone: 'fix' },
  Removed: { label: '제거', tone: 'remove' },
  Deprecated: { label: '지원 중단', tone: 'remove' },
  Security: { label: '보안', tone: 'fix' },
  'Upgrade notes': { label: '업그레이드 안내', tone: 'note' },
}

export function sectionMeta(title) {
  return SECTION_META[title] || { label: title, tone: 'default' }
}
