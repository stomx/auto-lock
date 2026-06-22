// 기능 카드용 stroke SVG 아이콘 세트. 이모지 대신 사용해 다크+라임 톤과 일관.
// currentColor를 쓰므로 .feature-icon 의 color(=accent-ink)로 틴트된다.

const base = {
  width: 26, height: 26, viewBox: '0 0 24 24', fill: 'none',
  stroke: 'currentColor', strokeWidth: 1.7, strokeLinecap: 'round', strokeLinejoin: 'round',
  'aria-hidden': true,
}

export const ICONS = {
  lock: (
    <svg {...base}><rect x="4.5" y="11" width="15" height="9.5" rx="2" /><path d="M8 11V7.5a4 4 0 0 1 8 0V11" /></svg>
  ),
  wake: (
    <svg {...base}><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" /></svg>
  ),
  unlock: (
    <svg {...base}><rect x="4.5" y="11" width="15" height="9.5" rx="2" /><path d="M8 11V7.5a4 4 0 0 1 7.7-1.5" /><path d="M12 15v2.5" /></svg>
  ),
  update: (
    <svg {...base}><path d="M21 12a9 9 0 1 1-2.6-6.4" /><path d="M21 4v4h-4" /></svg>
  ),
  shield: (
    <svg {...base}><path d="M12 3l7 3v5c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z" /><path d="M9.5 12l1.8 1.8 3.4-3.6" /></svg>
  ),
  menubar: (
    <svg {...base}><rect x="3" y="4" width="18" height="14" rx="2" /><path d="M3 8h18" /><circle cx="6.5" cy="6" r="0.6" fill="currentColor" /><path d="M9 21h6" /></svg>
  ),
}
