import { Outlet } from 'react-router-dom'
import NavBar from './NavBar.jsx'

// 공통 셸: skip-link(접근성) + 상단 고정 내비 + 본문(Outlet).
// Footer는 각 페이지의 스크롤 컨텍스트 안에 둔다 — Home은 .snap-root가
// 자체 스크롤을 가지므로, 그 안에 Footer가 있어야 스크롤 끝에서 보인다.
export default function Layout() {
  return (
    <>
      <a className="skip-link" href="#main">본문 바로가기</a>
      <NavBar />
      <main id="main">
        <Outlet />
      </main>
    </>
  )
}
