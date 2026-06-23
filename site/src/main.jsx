import React from 'react'
import ReactDOM from 'react-dom/client'
import { HashRouter, Routes, Route } from 'react-router-dom'
import { LazyMotion, domAnimation } from 'framer-motion'
import { ThemeProvider } from './lib/ThemeContext.jsx'
import Layout from './components/Layout.jsx'
import Home from './pages/Home.jsx'
import Changelog from './pages/Changelog.jsx'
import './styles.css'

// LazyMotion + m 컴포넌트: framer-motion의 무거운 feature 번들 대신
// domAnimation(변환·페이드·exit·variants)만 로드한다. layout/drag는 안 쓰므로
// 제외 → 번들 축소. strict 모드로 m 대신 motion.* 를 쓰면 런타임 에러로 잡힌다.
//
// HashRouter: GitHub Pages 같은 정적 호스팅에서 서버 라우팅 설정 없이
// /#/changelog 형태로 동작하게 한다(새로고침 404 회피).
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <LazyMotion features={domAnimation} strict>
      <ThemeProvider>
        <HashRouter>
          <Routes>
            <Route element={<Layout />}>
              <Route index element={<Home />} />
              <Route path="changelog" element={<Changelog />} />
            </Route>
          </Routes>
        </HashRouter>
      </ThemeProvider>
    </LazyMotion>
  </React.StrictMode>
)
