import { Link } from 'react-router-dom'
import { SCREENSHOTS, FEATURES, STEPS, INSTALL_URL } from '../data/content.js'
import Section from '../components/Section.jsx'
import DownloadButtons from '../components/DownloadButtons.jsx'
import ScreenshotGallery from '../components/ScreenshotGallery.jsx'
import FeatureCard from '../components/FeatureCard.jsx'
import InlineMarkdown from '../components/InlineMarkdown.jsx'
import ParallaxHero from '../components/ParallaxHero.jsx'
import ParallaxImage from '../components/ParallaxImage.jsx'
import CountdownAnimation from '../components/CountdownAnimation.jsx'
import Reveal from '../components/Reveal.jsx'
import Footer from '../components/Footer.jsx'
import PageIndicator from '../components/PageIndicator.jsx'
import { ICONS } from '../components/Icons.jsx'

// 우측 도트 네비가 추적할 섹션 목록(순서 = 스냅 순서).
// countdown+unlock을 'detail' 한 섹션으로 통합해 다운로드까지 단계를 줄였다.
const SECTIONS = [
  { id: 'hero', label: '소개' },
  { id: 'screens', label: '한눈에 보기' },
  { id: 'features', label: '주요 기능' },
  { id: 'how', label: '동작 방식' },
  { id: 'detail', label: '잠금 & 해제' },
  { id: 'download', label: '다운로드' },
]

export default function Home() {
  return (
    <div className="snap-root">
      <PageIndicator sections={SECTIONS} />
      <ParallaxHero />

      {/* 스크린샷 */}
      <Section
        id="screens"
        snap
        title="한눈에 보기"
        lead="메뉴바에서 근접 상태·신호 강도·등록 디바이스를 확인하고, 거리 임계값을 조절합니다."
      >
        <ScreenshotGallery shots={SCREENSHOTS} />
      </Section>

      {/* 기능 */}
      <Section
        id="features"
        snap
        title="주요 기능"
        lead="자리를 비우는 순간을 신호 강도로 감지해, 깜빡 잊고 두고 간 Mac을 대신 잠급니다."
      >
        <div className="features">
          {FEATURES.map((f, i) => (
            <Reveal key={f.title} delay={(i % 3) * 0.08}>
              <FeatureCard {...f} />
            </Reveal>
          ))}
        </div>
      </Section>

      {/* 동작 방식 */}
      <Section
        id="how"
        snap
        title="동작 방식"
        lead="단일 임계값과 신호 끊김 허용 시간으로 잠금을 결정합니다."
      >
        <ol className="steps">
          {STEPS.map((step, i) => (
            <Reveal as="li" className="step" key={i} delay={i * 0.06}>
              <span className="step-num">{i + 1}</span>
              <p>
                <InlineMarkdown text={step} />
              </p>
            </Reveal>
          ))}
        </ol>
      </Section>

      {/* 잠금 & 해제 (카운트다운 + 자동 해제 통합) */}
      <Section id="detail" snap title="잠그고, 다시 풀고" center>
        <div className="detail narrow">
          <div className="detail-pic">
            <CountdownAnimation />
          </div>
          <Reveal>
            <h3>잠금이 임박하면 알려줍니다</h3>
            <p>
              카운트다운 마지막 5초 동안 화면 한가운데에 큰 숫자가 5 → 4 → 3 → 2 → 1 로
              표시됩니다. 이 사이에 다시 가까워지면 즉시 초기화되어, 잠깐 자리를 비웠다
              돌아오는 경우엔 잠기지 않습니다.
            </p>
          </Reveal>
        </div>

        <div className="detail flip-mobile" style={{ marginTop: '40px' }}>
          <Reveal>
            <h3>자동 잠금 해제 (실험적)</h3>
            <p>
              근접 복귀 시 Keychain에 저장한 로그인 암호를 자동 입력합니다. 암호는{' '}
              <strong>macOS Keychain에만 저장</strong>되며 외부로 전송되지 않습니다.
            </p>
            <div className="note">
              일부 보안 환경에선 화면 깨우기까지만 동작합니다. 가장 안정적인 해제는 macOS
              기본 기능인 <strong>Apple Watch Auto Unlock</strong>과 함께 쓰는 것입니다.
            </div>
          </Reveal>
          <div className="detail-pic">
            <ParallaxImage src="images/password-sheet.png" alt="로그인 암호 저장 화면" strength={32} />
          </div>
        </div>
      </Section>

      {/* 다운로드 + 푸터 (마지막 화면 — 푸터까지 담도록 auto 높이) */}
      <Section
        id="download"
        snap
        free
        title="지금 사용해 보세요"
        lead="Apple Silicon Mac에서 macOS 13 이상이면 바로 쓸 수 있습니다."
      >
        <Reveal>
          <DownloadButtons variant="download" />

          {/* 신뢰 신호 */}
          <div className="trust-row">
            <span className="trust-badge">{ICONS.shield} 로컬에서만 동작</span>
            <span className="trust-badge">{ICONS.update} 오픈소스</span>
            <span className="trust-badge">{ICONS.lock} Keychain 저장</span>
          </div>

          {/* 미서명 설치 안내(펼침) — 다운로드 직후 마주칠 마찰을 미리 해소 */}
          <details className="install-note">
            <summary>처음 실행할 때 "확인되지 않은 개발자" 안내가 뜨나요?</summary>
            <ol>
              <li>AutoLock은 오픈소스라 Apple 유료 서명 대신 자체 서명을 씁니다 — 코드는 GitHub에서 공개 검증됩니다.</li>
              <li>처음 한 번만: <strong>앱을 우클릭 → 열기</strong>를 누르면 macOS 보안 안내에 "열기" 버튼이 생깁니다.</li>
              <li>
                자세한 절차는{' '}
                <a href={INSTALL_URL} target="_blank" rel="noreferrer">설치 안내</a>를 참고하세요.
              </li>
            </ol>
          </details>

          <p className="hero-req center">
            전체 변경 이력은 <Link to="/changelog">변경 이력</Link>에서 확인하세요.
          </p>
        </Reveal>
        <Footer />
      </Section>
    </div>
  )
}
