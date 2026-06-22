// 빌드 후처리 프리렌더: headless Chromium으로 빌드된 사이트를 실제 렌더한 뒤
// 그 #root 마크업을 dist/index.html에 주입한다. → JS를 실행하지 않는 크롤러
// (Bing/네이버 등)에게도 hero·기능·다운로드 본문 텍스트가 보인다.
//
// 브라우저 선택(폴백 체인):
//   1) PUPPETEER 번들 Chromium (CI/Cloudflare Pages에서 npm install로 받아짐)
//   2) 시스템 Chrome/Chromium (로컬 macOS)
// puppeteer.launch()가 일부 환경에서 spawn에 실패하므로, executablePath만
// puppeteer에서 얻고 실제 실행은 `chrome --headless --dump-dom`(검증된 경로)으로.
//
// React는 클라이언트에서 createRoot로 마운트하며 기존 #root 내용을 교체하므로
// hydration mismatch가 없다(프리렌더 마크업은 SEO·초기표시용, JS가 곧 대체).
import { spawn, spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const SITE = resolve(__dirname, '..')
const DIST_HTML = resolve(SITE, 'dist/index.html')
const PORT = 4793
const URL = `http://localhost:${PORT}/`

// ── 1) Chromium 실행 파일 찾기 ──
// 시스템 Chrome 우선(로컬 macOS에서 검증 가능) → puppeteer 번들 폴백(CI/Linux).
// CHROME_BIN 환경변수로 강제 지정도 가능.
async function findChrome() {
  if (process.env.CHROME_BIN && existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium-browser',
    '/usr/bin/chromium',
  ]
  const sys = candidates.find((c) => existsSync(c))
  if (sys) return sys
  // 폴백: puppeteer가 install 시 받은 Chromium (CI/Cloudflare Pages Linux)
  try {
    const puppeteer = (await import('puppeteer')).default
    const p = puppeteer.executablePath()
    if (p && existsSync(p)) return p
  } catch {}
  return null
}

if (!existsSync(DIST_HTML)) {
  console.error('❌ dist/index.html이 없습니다. 먼저 vite build를 실행하세요.')
  process.exit(1)
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
let server

function cleanup() { try { server?.kill() } catch {} }
process.on('exit', cleanup)
process.on('SIGINT', () => { cleanup(); process.exit(1) })

try {
  const chrome = await findChrome()
  if (!chrome) {
    console.error('⚠ Chromium을 찾지 못해 프리렌더를 건너뜁니다(SPA로만 배포).')
    process.exit(0)
  }

  // 2) vite preview 임시 서버
  console.log('▶ vite preview 임시 서버 기동...')
  server = spawn('npx', ['vite', 'preview', '--port', String(PORT), '--strictPort'], {
    cwd: SITE, stdio: 'ignore',
  })
  let up = false
  for (let i = 0; i < 48; i++) {
    await sleep(250)
    const probe = spawnSync('curl', ['-s', '-o', '/dev/null', '-w', '%{http_code}', URL], { encoding: 'utf8' })
    if (probe.stdout.trim() === '200') { up = true; break }
  }
  if (!up) throw new Error('preview 서버가 시간 내 응답하지 않음')

  // 3) headless 렌더 → DOM 덤프 (--no-sandbox: CI/일부 macOS 환경 필수)
  console.log(`▶ headless 렌더링 (${chrome.includes('puppeteer') ? 'puppeteer Chromium' : 'system Chrome'})...`)
  const res = spawnSync(
    chrome,
    ['--headless=new', '--no-sandbox', '--disable-setuid-sandbox', '--disable-gpu',
     '--disable-dev-shm-usage', '--hide-scrollbars', '--virtual-time-budget=6000', '--dump-dom', URL],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }
  )
  const rendered = res.stdout || ''
  const startIdx = rendered.indexOf('<div id="root">')
  if (startIdx === -1) throw new Error('렌더 결과에서 #root를 찾지 못함')

  // <div id="root">…</div> 의 매칭 닫는 태그까지 정확히 추출(div 깊이 카운트)
  const afterRoot = rendered.slice(startIdx)
  let depth = 0, i = afterRoot.indexOf('>') + 1, end = -1
  for (; i < afterRoot.length; i++) {
    if (afterRoot.startsWith('<div', i)) depth++
    else if (afterRoot.startsWith('</div>', i)) {
      if (depth === 0) { end = i + 6; break }
      depth--
    }
  }
  if (end === -1) throw new Error('#root 닫는 태그 매칭 실패')
  const rootHtml = afterRoot.slice(0, end)

  const innerHtml = rootHtml.slice(rootHtml.indexOf('>') + 1, rootHtml.length - '</div>'.length)
  const textLen = innerHtml.replace(/<[^>]+>/g, '').replace(/\s+/g, '').length
  if (textLen < 200) throw new Error(`렌더 본문이 너무 짧음(${textLen}자) — 렌더 실패 의심`)

  // 4) 빈 #root를 렌더된 마크업으로 치환
  let html = readFileSync(DIST_HTML, 'utf8')
  if (!html.includes('<div id="root"></div>')) {
    console.warn('⚠ dist/index.html에 빈 <div id="root"></div>가 없습니다(이미 프리렌더됨?).')
  } else {
    writeFileSync(DIST_HTML, html.replace('<div id="root"></div>', rootHtml))
  }
  console.log(`✅ 프리렌더 완료 — 본문 ${textLen}자 주입 (dist/index.html)`)
} catch (err) {
  // 프리렌더 실패가 배포 전체를 막지 않도록(SPA는 JS로 정상 동작, 구글봇은 JS 렌더).
  console.error('⚠ 프리렌더 실패 — SPA(JS 렌더)로만 배포됩니다:', err.message)
} finally {
  cleanup()
}
