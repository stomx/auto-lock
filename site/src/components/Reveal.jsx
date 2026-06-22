import { motion } from 'framer-motion'
import { useMotionEnabled, REVEAL_TRANSITION, VIEWPORT } from '../lib/motion.js'

// 스크롤 진입 시 페이드 + 위로 슬라이드인. delay로 스태거(순차 등장) 가능.
// reduced-motion이면 효과 없이 그대로 렌더.
export default function Reveal({ children, delay = 0, y = 28, as = 'div', className }) {
  const enabled = useMotionEnabled()
  const MotionTag = motion[as] || motion.div

  if (!enabled) {
    const Tag = as
    return <Tag className={className}>{children}</Tag>
  }

  return (
    <MotionTag
      className={className}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={VIEWPORT}
      transition={{ ...REVEAL_TRANSITION, delay }}
    >
      {children}
    </MotionTag>
  )
}
