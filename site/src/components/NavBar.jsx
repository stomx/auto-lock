import { Link, NavLink } from 'react-router-dom'
import { asset } from '../lib/asset.js'
import { REPO } from '../data/content.js'
import { useLatestDmg } from '../lib/release.js'
import ThemeControls from './ThemeControls.jsx'

export default function NavBar() {
  const { href: downloadHref } = useLatestDmg()
  return (
    <nav className="nav">
      <div className="wrap nav-inner">
        <Link to="/" className="brand">
          <img src={asset('images/icon.svg')} alt="" className="brand-icon" />
          <span>AutoLock</span>
        </Link>
        <div className="nav-links">
          <NavLink to="/" end className={({ isActive }) => (isActive ? 'active' : '')}>
            소개
          </NavLink>
          <NavLink to="/changelog" className={({ isActive }) => (isActive ? 'active' : '')}>
            변경 이력
          </NavLink>
          <a href={REPO} target="_blank" rel="noreferrer">
            GitHub ↗
          </a>
          <a className="nav-download" href={downloadHref}>
            다운로드
          </a>
          <ThemeControls />
        </div>
      </div>
    </nav>
  )
}
