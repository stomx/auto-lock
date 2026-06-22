import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// 배포 대상은 커스텀 도메인 루트(https://auto-lock.stomx.net/) → base '/'.
// GitHub Pages 프로젝트 경로(stomx.github.io/auto-lock/)로 배포할 때만
// VITE_BASE=/auto-lock/ 를 주면 그 경로로 빌드된다. 기본은 루트.
export default defineConfig(() => ({
  plugins: [react()],
  base: process.env.VITE_BASE || '/',
}))
