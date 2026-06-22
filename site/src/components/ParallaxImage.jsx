import { useRef } from 'react'
import { motion, useScroll, useTransform } from 'framer-motion'
import { useMotionEnabled } from '../lib/motion.js'
import { asset } from '../lib/asset.js'

// 요소가 뷰포트를 지나는 동안 이미지를 strength(px)만큼 천천히 떠오르게 한다.
// 컨테이너 기준 스크롤 진행도(0~1)를 y 이동으로 매핑하는 진짜 패럴렉스.
export default function ParallaxImage({ src, alt, strength = 40, className }) {
  const enabled = useMotionEnabled()
  const ref = useRef(null)
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start end', 'end start'],
  })
  // 들어올 때 +strength → 나갈 때 -strength 로 부드럽게 이동.
  const y = useTransform(scrollYProgress, [0, 1], [strength, -strength])

  if (!enabled) {
    return <img src={asset(src)} alt={alt} className={className} loading="lazy" />
  }

  return (
    <motion.img
      ref={ref}
      src={asset(src)}
      alt={alt}
      className={className}
      style={{ y, willChange: 'transform' }}
      loading="lazy"
    />
  )
}
