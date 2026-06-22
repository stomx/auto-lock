import { asset } from '../lib/asset.js'
import Reveal from './Reveal.jsx'

// 스크린샷 그리드. 각 카드를 스태거(순차) reveal로 등장시킨다.
export default function ScreenshotGallery({ shots }) {
  return (
    <div className="gallery">
      {shots.map((shot, i) => (
        <Reveal as="figure" className="shot" key={shot.src} delay={i * 0.1}>
          <img src={asset(shot.src)} alt={shot.caption} loading="lazy" />
          <figcaption>{shot.caption}</figcaption>
        </Reveal>
      ))}
    </div>
  )
}
