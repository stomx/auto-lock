import { useState, useEffect, useRef } from 'react'
import { motion, AnimatePresence, useScroll, useTransform, useInView } from 'framer-motion'
import { useMotionEnabled } from '../lib/motion.js'

// 실제 CountdownOverlay(앱)를 CSS로 재현 + 5→4→3→2→1→잠금 순환 애니메이션.
// - 화면(뷰포트)에 보일 때만 진행하고, 벗어나면 멈춘다.
// - 다시 보이면 항상 처음(5)부터 시작한다.
// - reduced-motion이면 정적으로 "5"만 표시(원래 스크린샷과 동일한 모습).

const SEQUENCE = [5, 4, 3, 2, 1, 'lock'] // 'lock' = 잠금 화면 샘플
const STEP_MS = 1000 // 숫자 전환 간격
const LOCK_MS = 3000 // 잠금 화면 머무는 시간

// 흰색 자물쇠 아이콘(잠금 단계).
function LockGlyph() {
  return (
    <svg viewBox="0 0 24 24" width="46%" height="46%" fill="none"
         stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"
         aria-hidden="true">
      <rect x="4.5" y="10.5" width="15" height="10.5" rx="2.2" />
      <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />
      <circle cx="12" cy="15.4" r="1.3" fill="currentColor" stroke="none" />
      <path d="M12 16.4v2.2" />
    </svg>
  )
}

export default function CountdownAnimation() {
  const enabled = useMotionEnabled()
  const [index, setIndex] = useState(0)
  const timerRef = useRef(null)

  const ref = useRef(null)
  // 뷰포트에 절반 이상 보일 때만 활성. 벗어나면 inView=false → 정지.
  const inView = useInView(ref, { amount: 0.5 })

  // 패럴렉스 드리프트(스크린샷처럼 떠오르게) — reduced-motion이면 0.
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start end', 'end start'] })
  const y = useTransform(scrollYProgress, [0, 1], [36, -36])

  // 화면에서 벗어나면 인덱스를 0으로 리셋해, 다시 보일 때 항상 5부터 시작.
  useEffect(() => {
    if (!inView) setIndex(0)
  }, [inView])

  // 보이는 동안에만 다음 스텝으로 진행. 안 보이거나 모션 끄면 타이머 미설정.
  useEffect(() => {
    if (!enabled || !inView) return
    const current = SEQUENCE[index]
    const delay = current === 'lock' ? LOCK_MS : STEP_MS
    timerRef.current = setTimeout(() => {
      setIndex((i) => (i + 1) % SEQUENCE.length)
    }, delay)
    return () => clearTimeout(timerRef.current)
  }, [index, enabled, inView])

  const value = enabled ? SEQUENCE[index] : 5
  const isLock = value === 'lock'

  const box = (
    <div className={`cd-box${isLock ? ' cd-box-lock' : ''}`} role="img"
         aria-label="카운트다운 오버레이 미리보기">
      {enabled ? (
        <AnimatePresence mode="wait">
          <motion.div
            key={String(value)}
            className="cd-digit"
            initial={{ opacity: 0, scale: 0.6 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 1.4 }}
            transition={{ duration: 0.32, ease: [0.22, 1, 0.36, 1] }}
          >
            {isLock ? <LockGlyph /> : value}
          </motion.div>
        </AnimatePresence>
      ) : (
        <div className="cd-digit">5</div>
      )}
    </div>
  )

  if (!enabled) {
    return <div ref={ref}>{box}</div>
  }

  return (
    <motion.div ref={ref} style={{ y, willChange: 'transform' }}>
      {box}
    </motion.div>
  )
}
