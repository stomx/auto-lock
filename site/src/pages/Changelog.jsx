import changelogRaw from '../data/CHANGELOG.md?raw'
import { parseChangelog } from '../lib/parseChangelog.js'
import ReleaseCard from '../components/ReleaseCard.jsx'
import Reveal from '../components/Reveal.jsx'
import Footer from '../components/Footer.jsx'
import { REPO } from '../data/content.js'

// CHANGELOG.md(단일 소스)를 빌드 타임에 raw로 import해 파싱한다.
// 모듈 로드 시 1회만 계산되므로 렌더마다 다시 파싱하지 않는다.
const releases = parseChangelog(changelogRaw)

export default function Changelog() {
  return (
    <div className="changelog">
      <div className="wrap">
        <header className="changelog-head">
          <h1>변경 이력</h1>
          <p>
            형식은 <a href="https://keepachangelog.com/ko/1.1.0/" target="_blank" rel="noreferrer">Keep a Changelog</a>,
            버전은 <a href="https://semver.org/lang/ko/" target="_blank" rel="noreferrer">Semantic Versioning</a>을 따릅니다.
            원문은 <a href={`${REPO}/blob/main/CHANGELOG.md`} target="_blank" rel="noreferrer">CHANGELOG.md</a>.
          </p>
        </header>

        <div className="timeline">
          {releases.map((release, i) => (
            <Reveal key={release.version} delay={Math.min(i, 4) * 0.05}>
              <ReleaseCard release={release} latest={i === 0} />
            </Reveal>
          ))}
        </div>
      </div>
      <Footer />
    </div>
  )
}
