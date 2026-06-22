// 빌드 후처리 프리렌더: 시스템 Chrome(headless)으로 빌드된 사이트를 실제 렌더한 뒤
// 그 #root 마크업을 dist/index.html에 주입한다. → JS를 실행하지 않는 크롤러
// (Bing/네이버 등)에게도 hero·기능·다운로드 본문 텍스트가 보인다.
//
// puppeteer 등 무거운 의존성 없이 시스템 Chrome만 사용. React는 클라이언트에서
// createRoot로 마운트하며 기존 #root 내용을 교체하므로 hydration mismatch가 없다.
//
// 흐름: vite preview(임시 서버) → chrome --dump-dom → #root 추출 → dist/index.html 치환.
import { spawn, spawnSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const SITE = resolve(__dirname, '..')
const DIST_HTML = resolve(SITE, 'dist/index.html')
const PORT = 4793
const URL = `http://localhost:${PORT}/`

const CHROME_CANDIDATES = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
  '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
]
const chrome = CHROME_CANDIDATES.find((p) => existsSync(p))
if (!chrome) {
  console.error('❌ 프리렌더용 Chrome/Chromium을 찾지 못했습니다. 프리렌더를 건너뜁니다.')
  process.exit(0) // 빌드 자체는 실패시키지 않음(프리렌더는 향상 단계)
}
if (!existsSync(DIST_HTML)) {
  console.error('❌ dist/index.html이 없습니다. 먼저 vite build를 실행하세요.')
  process.exit(1)
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// 1) vite preview 임시 서버 기동
console.log('▶ vite preview 임시 서버 기동...')
const server = spawn('npx', ['vite', 'preview', '--port', String(PORT), '--strictPort'], {
  cwd: SITE,
  stdio: 'ignore',
})

const cleanup = () => { try { server.kill() } catch {} }
process.on('exit', cleanup)
process.on('SIGINT', () => { cleanup(); process.exit(1) })

try {
  // 서버가 응답할 때까지 대기(최대 ~10초)
  let up = false
  for (let i = 0; i < 40; i++) {
    await sleep(250)
    const probe = spawnSync('curl', ['-s', '-o', '/dev/null', '-w', '%{http_code}', URL], { encoding: 'utf8' })
    if (probe.stdout.trim() === '200') { up = true; break }
  }
  if (!up) throw new Error('preview 서버가 시간 내 응답하지 않음')

  // 2) Chrome headless로 렌더된 DOM 추출
  console.log('▶ Chrome headless 렌더링...')
  const res = spawnSync(
    chrome,
    ['--headless', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
     '--virtual-time-budget=5000', '--dump-dom', URL],
    { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }
  )
  const rendered = res.stdout || ''
  const m = rendered.match(/<div id="root">([\s\S]*?)<\/div>\s*<!--/)
    || rendered.match(/<div id="root">([\s\S]*)<\/div><script/)
  // 더 견고하게: #root 시작부터 매칭(스크립트 직전까지)
  const startIdx = rendered.indexOf('<div id="root">')
  if (startIdx === -1) throw new Error('렌더 결과에서 #root를 찾지 못함')
  // #root의 닫는 태그 위치: 그 뒤 첫 <script 또는 </body> 전까지를 본문으로 본다.
  const afterRoot = rendered.slice(startIdx)
  // <div id="root">…</div> 의 매칭 div 깊이 계산
  let depth = 0, i = afterRoot.indexOf('>') + 1, end = -1
  for (; i < afterRoot.length; i++) {
    if (afterRoot.startsWith('<div', i)) depth++
    else if (afterRoot.startsWith('</div>', i)) {
      if (depth === 0) { end = i + 6; break }
      depth--
    }
  }
  if (end === -1) throw new Error('#root 닫는 태그 매칭 실패')
  const rootHtml = afterRoot.slice(0, end) // <div id="root">…</div> 전체

  const innerStart = rootHtml.indexOf('>') + 1
  const innerHtml = rootHtml.slice(innerStart, rootHtml.length - '</div>'.length)
  const textLen = innerHtml.replace(/<[^>]+>/g, '').replace(/\s+/g, '').length
  if (textLen < 200) throw new Error(`렌더 본문이 너무 짧음(${textLen}자) — 렌더 실패 의심`)

  // 3) dist/index.html의 빈 #root를 렌더된 마크업으로 치환
  let html = readFileSync(DIST_HTML, 'utf8')
  if (!html.includes('<div id="root"></div>')) {
    console.warn('⚠ dist/index.html에 빈 <div id="root"></div>가 없습니다(이미 프리렌더됨?). 그대로 둡니다.')
  } else {
    html = html.replace('<div id="root"></div>', rootHtml)
    writeFileSync(DIST_HTML, html)
  }
  console.log(`✅ 프리렌더 완료 — 본문 ${textLen}자 주입 (dist/index.html)`)
} finally {
  cleanup()
}
