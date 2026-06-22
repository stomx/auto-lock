import { useReducedMotion } from 'framer-motion'

// 프로젝트 전역 모션 정책을 한 곳에서 관리한다.
// prefers-reduced-motion(OS 접근성 설정)이 켜져 있으면 모든 패럴렉스·reveal을
// 비활성화하도록 컴포넌트들이 이 훅을 참조한다.
export function useMotionEnabled() {
  const reduced = useReducedMotion()
  return !reduced
}

// reveal(스크롤 진입 페이드+슬라이드) 공통 트랜지션.
export const REVEAL_TRANSITION = { duration: 0.6, ease: [0.22, 1, 0.36, 1] }

// viewport 진입 트리거 기본값: 한 번만, 약간 일찍.
export const VIEWPORT = { once: true, amount: 0.2, margin: '0px 0px -10% 0px' }
