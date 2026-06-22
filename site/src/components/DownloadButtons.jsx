import { DOWNLOAD_DMG, RELEASES_URL, REPO } from '../data/content.js'

// 다운로드 CTA. variant='hero'면 GitHub 보기, 'download'면 모든 릴리스로 보조 버튼이 바뀐다.
export default function DownloadButtons({ variant = 'hero' }) {
  const secondary =
    variant === 'hero'
      ? { href: REPO, label: 'GitHub에서 보기' }
      : { href: RELEASES_URL, label: '모든 릴리스' }

  return (
    <div className="cta-row">
      <a className="btn btn-primary" href={DOWNLOAD_DMG}>
        ⬇ 다운로드 (DMG)
      </a>
      <a className="btn btn-ghost" href={secondary.href} target="_blank" rel="noreferrer">
        {secondary.label}
      </a>
    </div>
  )
}
