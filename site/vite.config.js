import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { existsSync, readFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { latestRelease } from './src/lib/version.js'

const __dirname = dirname(fileURLToPath(import.meta.url))

// 버전 단일 출처(SSOT): repo 루트 CHANGELOG.md 최상단 릴리스.
// changelog 본문은 런타임에 GitHub(main)에서 받아 렌더하므로 번들에 넣지 않는다.
// 빌드 타임에 필요한 건 "최신 버전 문자열"뿐 — 히어로 표기·JSON-LD에 쓴다.
const ROOT_CHANGELOG = resolve(__dirname, '../CHANGELOG.md')

function ssotVersion() {
  const md = existsSync(ROOT_CHANGELOG) ? readFileSync(ROOT_CHANGELOG, 'utf8') : ''
  return latestRelease(md).version
}

// versionPlugin: index.html의 JSON-LD softwareVersion 자리표시자를 SSOT 버전으로 치환.
function versionPlugin(version) {
  return {
    name: 'autolock-version-ssot',
    transformIndexHtml(html) {
      return html.replace(/__APP_VERSION__/g, version)
    },
  }
}

// 배포 대상은 커스텀 도메인 루트(https://auto-lock.stomx.net/) → base '/'.
// GitHub Pages 프로젝트 경로(stomx.github.io/auto-lock/)로 배포할 때만
// VITE_BASE=/auto-lock/ 를 주면 그 경로로 빌드된다. 기본은 루트.
export default defineConfig(() => {
  const version = ssotVersion()
  return {
    plugins: [versionPlugin(version), react()],
    base: process.env.VITE_BASE || '/',
    // 앱 코드에서 import.meta 대신 쓰는 빌드 타임 상수. 버전은 여기 한 곳에서 주입.
    define: {
      __APP_VERSION__: JSON.stringify(version),
    },
    build: {
      rollupOptions: {
        output: {
          // vendor 분리: React 런타임과 애니메이션 라이브러리를 본 코드와 떼어
          // 장기 캐싱 효율을 높인다(앱 코드만 바뀌면 vendor 청크는 재다운로드 불필요).
          manualChunks: {
            react: ['react', 'react-dom', 'react-router-dom'],
            motion: ['framer-motion'],
          },
        },
      },
    },
  }
})
