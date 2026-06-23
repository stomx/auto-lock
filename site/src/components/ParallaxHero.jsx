import { useRef } from 'react'
import { m, useScroll, useTransform } from 'framer-motion'
import { useMotionEnabled } from '../lib/motion.js'
import { asset } from '../lib/asset.js'
import { HERO, LATEST_VERSION } from '../data/content.js'
import DownloadButtons from './DownloadButtons.jsx'

// 다층 패럴렉스 히어로: 배경 글로우 / 아이콘 / 텍스트가 스크롤에 서로 다른
// 속도로 움직여 깊이감을 준다. reduced-motion이면 정적 렌더.
export default function ParallaxHero() {
  const enabled = useMotionEnabled()
  const ref = useRef(null)
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start start', 'end start'], // 히어로 상단 고정 → 위로 빠져나갈 때까지
  })

  // 레이어별 이동량(뒤 레이어일수록 더 많이/느리게 움직임)·페이드.
  const glowY = useTransform(scrollYProgress, [0, 1], [0, 160])
  const iconY = useTransform(scrollYProgress, [0, 1], [0, 90])
  const textY = useTransform(scrollYProgress, [0, 1], [0, 40])
  const fade = useTransform(scrollYProgress, [0, 0.8], [1, 0])

  // reduced-motion: 스타일 객체를 비워 transform/opacity 애니메이션 제거.
  const sGlow = enabled ? { y: glowY } : undefined
  const sIcon = enabled ? { y: iconY, opacity: fade } : undefined
  const sText = enabled ? { y: textY, opacity: fade } : undefined

  return (
    <header className="hero" id="hero" ref={ref}>
      <m.div className="hero-glow" style={sGlow} aria-hidden="true" />
      <div className="wrap hero-content">
        <m.img
          className="hero-logo"
          src={asset('images/icon.svg')}
          alt="AutoLock 아이콘"
          style={sIcon}
        />
        <m.div style={sText}>
          <h1>{HERO.title}</h1>
          <p className="hero-tagline">{HERO.tagline}</p>
          <p className="hero-sub">{HERO.sub}</p>
          <DownloadButtons variant="hero" />
          <p className="hero-req">최신 버전 {LATEST_VERSION} · 첫 실행 시 Bluetooth 권한 허용 필요</p>
        </m.div>
      </div>
    </header>
  )
}
