// 체인지로그 본문의 인라인 마크다운만 안전하게 렌더한다.
// 지원: **굵게**, `코드`, [텍스트](url). 풀 마크다운 라이브러리 없이 가볍게.
// 토큰화 방식이라 HTML 주입 위험이 없다(dangerouslySetInnerHTML 미사용).

const TOKEN_RE = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)]+\))/g

export default function InlineMarkdown({ text }) {
  const parts = String(text).split(TOKEN_RE).filter((s) => s !== '')

  return (
    <>
      {parts.map((part, i) => {
        if (part.startsWith('**') && part.endsWith('**')) {
          return <strong key={i}>{part.slice(2, -2)}</strong>
        }
        if (part.startsWith('`') && part.endsWith('`')) {
          return <code key={i}>{part.slice(1, -1)}</code>
        }
        const link = part.match(/^\[([^\]]+)\]\(([^)]+)\)$/)
        if (link) {
          return (
            <a key={i} href={link[2]} target="_blank" rel="noreferrer">
              {link[1]}
            </a>
          )
        }
        return <span key={i}>{part}</span>
      })}
    </>
  )
}
