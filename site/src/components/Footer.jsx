import { REPO } from '../data/content.js'

export default function Footer() {
  return (
    <footer className="footer">
      <div className="wrap">
        <p>
          AutoLock · 오픈소스 macOS 메뉴바 앱 ·{' '}
          <a href={REPO} target="_blank" rel="noreferrer">
            github.com/stomx/auto-lock
          </a>
        </p>
      </div>
    </footer>
  )
}
