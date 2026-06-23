import { RELEASES_URL, REPO } from '../data/content.js'
import { useLatestDmg } from '../lib/release.js'

// 다운로드 CTA. variant='hero'면 GitHub 보기, 'download'면 모든 릴리스로 보조 버튼이 바뀐다.
// 기본 href는 빌드 타임 폴백(SSOT 버전)이고, 마운트 후 GitHub API로 받은 실제
// 최신 .dmg URL로 교체된다. JS 비활성/프리렌더 시에도 폴백 링크가 동작한다.
export default function DownloadButtons({ variant = 'hero' }) {
  const { href } = useLatestDmg()
  const secondary =
    variant === 'hero'
      ? { href: REPO, label: 'GitHub에서 보기' }
      : { href: RELEASES_URL, label: '모든 릴리스' }

  return (
    <div className="cta-row">
      <a className="btn btn-primary" href={href}>
        ⬇ 다운로드 (DMG)
      </a>
      <a className="btn btn-ghost" href={secondary.href} target="_blank" rel="noreferrer">
        {secondary.label}
      </a>
    </div>
  )
}
