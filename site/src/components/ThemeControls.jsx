import { useTheme } from '../lib/ThemeContext.jsx'

// 3-way 테마 선택: System / Dark / Light. 세그먼티드 컨트롤.
const OPTIONS = [
  { key: 'system', label: '시스템', icon: SystemIcon },
  { key: 'light', label: '라이트', icon: SunIcon },
  { key: 'dark', label: '다크', icon: MoonIcon },
]

export default function ThemeControls() {
  const { preference, setTheme } = useTheme()

  return (
    <div className="theme-seg" role="radiogroup" aria-label="테마 선택">
      {OPTIONS.map(({ key, label, icon: Icon }) => (
        <button
          key={key}
          className={`theme-seg-btn${preference === key ? ' active' : ''}`}
          onClick={() => setTheme(key)}
          role="radio"
          aria-checked={preference === key}
          aria-label={label}
          title={label}
        >
          <Icon />
        </button>
      ))}
    </div>
  )
}

function SunIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
         strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  )
}

function MoonIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
         strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
    </svg>
  )
}

function SystemIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
         strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <rect x="3" y="4" width="18" height="12" rx="2" />
      <path d="M8 20h8M12 16v4" />
    </svg>
  )
}
