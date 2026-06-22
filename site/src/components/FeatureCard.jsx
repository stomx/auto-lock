import { ICONS } from './Icons.jsx'

// 기능 카드 하나. icon은 ICONS 키. 표현만 담당.
export default function FeatureCard({ icon, title, body }) {
  return (
    <div className="feature">
      <div className="feature-icon">{ICONS[icon]}</div>
      <h3>{title}</h3>
      <p>{body}</p>
    </div>
  )
}
