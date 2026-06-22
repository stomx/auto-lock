import React from 'react'
import ReactDOM from 'react-dom/client'
import { HashRouter, Routes, Route } from 'react-router-dom'
import { ThemeProvider } from './lib/ThemeContext.jsx'
import Layout from './components/Layout.jsx'
import Home from './pages/Home.jsx'
import Changelog from './pages/Changelog.jsx'
import './styles.css'

// HashRouter: GitHub Pages 같은 정적 호스팅에서 서버 라우팅 설정 없이
// /#/changelog 형태로 동작하게 한다(새로고침 404 회피).
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
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
  </React.StrictMode>
)
