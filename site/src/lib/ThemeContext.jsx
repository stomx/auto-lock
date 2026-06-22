import { createContext, useContext, useState, useEffect, useCallback } from 'react'

const STORAGE_THEME = 'autolock.theme'
const PREFERS_DARK = '(prefers-color-scheme: dark)'

const ThemeContext = createContext(null)

// 저장된 사용자 선택: 'system' | 'dark' | 'light'. 없으면 system.
function initialPreference() {
  const saved = localStorage.getItem(STORAGE_THEME)
  return saved === 'dark' || saved === 'light' || saved === 'system' ? saved : 'system'
}

// 선택값을 실제 적용 테마로 해석(system이면 OS 설정 따라감).
function resolve(preference) {
  if (preference === 'system') {
    return window.matchMedia?.(PREFERS_DARK).matches ? 'dark' : 'light'
  }
  return preference
}

export function ThemeProvider({ children }) {
  const [preference, setPreference] = useState(initialPreference) // 사용자 선택
  const [resolved, setResolved] = useState(() => resolve(initialPreference()))

  // 선택값 → 실제 테마 반영 + 저장. <html data-theme>.
  useEffect(() => {
    const apply = () => setResolved(resolve(preference))
    apply()
    localStorage.setItem(STORAGE_THEME, preference)

    // system 모드일 때만 OS 설정 변화를 실시간 반영.
    if (preference === 'system') {
      const mq = window.matchMedia(PREFERS_DARK)
      mq.addEventListener('change', apply)
      return () => mq.removeEventListener('change', apply)
    }
  }, [preference])

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', resolved)
  }, [resolved])

  const setTheme = useCallback((pref) => setPreference(pref), [])

  return (
    <ThemeContext.Provider value={{ preference, resolved, setTheme }}>
      {children}
    </ThemeContext.Provider>
  )
}

export function useTheme() {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider')
  return ctx
}
