// 공통 섹션 래퍼: 제목 + 리드 문구 + 본문. 페이지마다 동일한 여백/정렬을 보장.
// snap=true면 풀스크린 스냅 타깃(.snap-section)이 된다. free=true면 한 화면을
// 넘는 긴 섹션이라 스냅에서 빠진다(.snap-free).
export default function Section({ id, title, lead, children, center = true, snap = false, free = false }) {
  const cls = ['section', snap && 'snap-section', snap && free && 'snap-free']
    .filter(Boolean)
    .join(' ')
  return (
    <section id={id} className={cls}>
      <div className="wrap">
        {title && <h2 className={center ? 'section-title center' : 'section-title'}>{title}</h2>}
        {lead && <p className="section-lead">{lead}</p>}
        {children}
      </div>
    </section>
  )
}
