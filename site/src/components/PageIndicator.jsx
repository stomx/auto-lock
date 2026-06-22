import { useState, useEffect } from 'react'
import { useMotionEnabled } from '../lib/motion.js'

// 우측 세로 도트 네비. snap-root 안의 .snap-section을 IntersectionObserver로
// 관찰해 현재 화면 섹션을 활성 표시하고, 클릭하면 해당 섹션으로 스크롤한다.
//
// sections: [{ id, label }]
export default function PageIndicator({ sections }) {
  const enabled = useMotionEnabled()
  const [active, setActive] = useState(0)

  useEffect(() => {
    const root = document.querySelector('.snap-root')
    const els = sections.map((s) => document.getElementById(s.id)).filter(Boolean)
    if (!root || els.length === 0) return

    const io = new IntersectionObserver(
      (entries) => {
        // 화면에 가장 많이 보이는 섹션을 활성으로.
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0]
        if (visible) {
          const idx = sections.findIndex((s) => s.id === visible.target.id)
          if (idx !== -1) setActive(idx)
        }
      },
      { root, threshold: [0.5, 0.6, 0.75] }
    )
    els.forEach((el) => io.observe(el))
    return () => io.disconnect()
  }, [sections])

  const jump = (id) => {
    document.getElementById(id)?.scrollIntoView({
      behavior: enabled ? 'smooth' : 'auto',
      block: 'start',
    })
  }

  return (
    <nav className="page-dots" aria-label="섹션 이동">
      {sections.map((s, i) => (
        <button
          key={s.id}
          className={`page-dot${i === active ? ' active' : ''}`}
          onClick={() => jump(s.id)}
          aria-label={s.label}
          aria-current={i === active ? 'true' : undefined}
        >
          <span className="page-dot-label">{s.label}</span>
        </button>
      ))}
    </nav>
  )
}
