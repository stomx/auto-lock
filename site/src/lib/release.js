import { useEffect, useState } from 'react'
import { DOWNLOAD_DMG, LATEST_VERSION, REPO } from '../data/content.js'

// GitHub Releases API로 "지금 이 순간"의 최신 릴리스 DMG 자산을 가져온다.
// 사이트는 정적으로 빌드되어 재배포 전까지 버전이 고정되지만, 앱은 그보다 자주
// 릴리스될 수 있다. 그 갭(사이트 빌드 ~ 다음 배포 사이의 새 릴리스)을 런타임에
// 메워, 다운로드 버튼이 항상 살아있는 .dmg를 가리키게 한다.
//
// 실패(네트워크·rate limit·JS 비활성) 시에는 빌드 타임 폴백을 그대로 쓴다.
const OWNER_REPO = REPO.replace('https://github.com/', '')
const LATEST_API = `https://api.github.com/repos/${OWNER_REPO}/releases/latest`

// 프리렌더(headless Chrome으로 DOM을 떠서 정적 HTML에 박는 단계)에서는
// fetch 결과가 그대로 굳어버린다. 그러면 새 릴리스가 나오고 사이트 재배포 전인
// 동안, JS 꺼진 방문자에게 옛 버전 직접 링크가 노출된다. 프리렌더에서는 fetch를
// 건너뛰어 정적 HTML에 'releases/latest/download/...' 폴백만 남기고, 실제 브라우저
// 방문자는 런타임에 최신으로 갱신되게 한다.
function isPrerender() {
  if (typeof navigator === 'undefined') return true
  return /HeadlessChrome/i.test(navigator.userAgent) || navigator.webdriver === true
}

// arm64 dmg 자산을 고른다(없으면 임의의 .dmg, 그것도 없으면 null).
function pickDmg(assets) {
  if (!Array.isArray(assets)) return null
  const arm = assets.find((a) => /arm64.*\.dmg$/i.test(a.name))
  const any = assets.find((a) => /\.dmg$/i.test(a.name))
  return (arm || any)?.browser_download_url || null
}

// useLatestDmg: { href, version } 를 반환한다. 초깃값은 빌드 타임 폴백이며,
// API 응답이 오면 실제 최신 자산 URL·태그로 교체된다.
export function useLatestDmg() {
  const [state, setState] = useState({ href: DOWNLOAD_DMG, version: LATEST_VERSION })

  useEffect(() => {
    if (isPrerender()) return // 프리렌더: 폴백(releases/latest/download) 유지
    let cancelled = false
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 4000) // 느린 네트워크에선 폴백 유지

    fetch(LATEST_API, {
      signal: ctrl.signal,
      headers: { Accept: 'application/vnd.github+json' },
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((data) => {
        if (cancelled) return
        const href = pickDmg(data.assets)
        if (href) setState({ href, version: data.tag_name || LATEST_VERSION })
      })
      .catch(() => {}) // 폴백 유지 — 조용히 실패
      .finally(() => clearTimeout(timer))

    return () => {
      cancelled = true
      clearTimeout(timer)
      ctrl.abort()
    }
  }, [])

  return state
}
