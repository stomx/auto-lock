import { useEffect, useState } from 'react'
import { parseChangelog } from '../lib/parseChangelog.js'
import ReleaseCard from '../components/ReleaseCard.jsx'
import Reveal from '../components/Reveal.jsx'
import Footer from '../components/Footer.jsx'
import { CHANGELOG_URL, CHANGELOG_RAW_URL } from '../data/content.js'

// 변경 이력은 빌드에 박지 않고 런타임에 GitHub(main 브랜치)의 CHANGELOG.md를
// 그대로 받아 렌더한다. → 사이트를 재배포하지 않아도 항상 최신이고, 번들에서
// 체인지로그 본문이 빠진다. 상단에 원문 링크를 항상 두어, fetch 실패(오프라인·
// rate limit) 시에도 사용자가 원문으로 갈 수 있게 한다(폴백).
export default function Changelog() {
  const [state, setState] = useState({ status: 'loading', releases: [] })

  useEffect(() => {
    let cancelled = false
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), 8000)

    fetch(CHANGELOG_RAW_URL, { signal: ctrl.signal })
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((md) => {
        if (cancelled) return
        const releases = parseChangelog(md)
        setState({ status: releases.length ? 'ready' : 'error', releases })
      })
      .catch(() => {
        if (!cancelled) setState({ status: 'error', releases: [] })
      })
      .finally(() => clearTimeout(timer))

    return () => {
      cancelled = true
      clearTimeout(timer)
      ctrl.abort()
    }
  }, [])

  const { status, releases } = state

  return (
    <div className="changelog">
      <div className="wrap">
        <header className="changelog-head">
          <h1>변경 이력</h1>
          <p>
            형식은 <a href="https://keepachangelog.com/ko/1.1.0/" target="_blank" rel="noreferrer">Keep a Changelog</a>,
            버전은 <a href="https://semver.org/lang/ko/" target="_blank" rel="noreferrer">Semantic Versioning</a>을 따릅니다.
            원문은 <a href={CHANGELOG_URL} target="_blank" rel="noreferrer">CHANGELOG.md</a>에서 확인할 수 있습니다.
          </p>
        </header>

        {status === 'loading' && (
          <p className="changelog-state" role="status">변경 이력을 불러오는 중…</p>
        )}

        {status === 'error' && (
          <p className="changelog-state">
            변경 이력을 불러오지 못했습니다.{' '}
            <a href={CHANGELOG_URL} target="_blank" rel="noreferrer">GitHub에서 원문 보기 ↗</a>
          </p>
        )}

        {status === 'ready' && (
          <div className="timeline">
            {releases.map((release, i) => (
              <Reveal key={release.version} delay={Math.min(i, 4) * 0.05}>
                <ReleaseCard release={release} latest={i === 0} />
              </Reveal>
            ))}
          </div>
        )}
      </div>
      <Footer />
    </div>
  )
}
