import { sectionMeta } from '../lib/parseChangelog.js'
import InlineMarkdown from './InlineMarkdown.jsx'

// 한 릴리스(버전)를 카드로. 버전·날짜 헤더 + 섹션별(추가/변경/수정...) 목록.
export default function ReleaseCard({ release, latest = false }) {
  return (
    <article className="release">
      <header className="release-head">
        <h3 className="release-version">
          v{release.version}
          {latest && <span className="badge-latest">최신</span>}
        </h3>
        {release.date && <time className="release-date">{release.date}</time>}
      </header>

      {release.sections.map((section, si) => {
        const meta = sectionMeta(section.title)
        return (
          <div className="release-section" key={si}>
            {section.title && <span className={`tag tag-${meta.tone}`}>{meta.label}</span>}
            <ul className="change-list">
              {section.items.map((item, ii) => (
                <li key={ii}>
                  <InlineMarkdown text={item} />
                </li>
              ))}
            </ul>
          </div>
        )
      })}
    </article>
  )
}
