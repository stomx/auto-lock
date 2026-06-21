import Testing
import Foundation
@testable import AutoLockCore

/// `diagnose update` / `diagnose self-update`가 공유하던 `--current`/`--feed`
/// 인자 파싱을 순수 타입으로 추출한 것에 대한 명세. 추출 전에는 두 서브커맨드에
/// 글자 단위로 복붙돼 있어 한쪽만 어긋날 수 있었고, 시스템콜과 뒤섞인 0% 커버리지
/// 타깃(AutoLock)에 묻혀 테스트가 불가능했다.
@Suite struct DiagnoseArgsTests {
    @Test func emptyArgsUsesDefaultCurrentAndNoFeed() {
        let result = DiagnoseArgs.parseCommon([], defaultCurrent: "1.2.3")
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.currentVersion == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(opts.feedURL == nil)
    }

    @Test func currentFlagOverridesDefault() {
        let result = DiagnoseArgs.parseCommon(["--current", "0.0.1"], defaultCurrent: "9.9.9")
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.currentVersion == SemanticVersion(major: 0, minor: 0, patch: 1))
    }

    @Test func currentFlagWithoutValueFallsBackToDefault() {
        // `--current`가 마지막 토큰이면 (뒤에 값이 없으면) 기존 동작은 무시하고
        // 기본값을 쓴다 (i + 1 < count 가드).
        let result = DiagnoseArgs.parseCommon(["--current"], defaultCurrent: "2.0.0")
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.currentVersion == SemanticVersion(major: 2, minor: 0, patch: 0))
    }

    @Test func unparseableCurrentFailsWithExactMessage() {
        let result = DiagnoseArgs.parseCommon(["--current", "garbage"], defaultCurrent: "1.0.0")
        #expect(result == .failure("❌ --current 버전 파싱 실패: garbage"))
    }

    @Test func unparseableDefaultCurrentFailsWhenNoFlag() {
        let result = DiagnoseArgs.parseCommon([], defaultCurrent: "not-a-version")
        #expect(result == .failure("❌ --current 버전 파싱 실패: not-a-version"))
    }

    @Test func feedFlagParsesURL() {
        let result = DiagnoseArgs.parseCommon(
            ["--feed", "https://example.com/releases.json"],
            defaultCurrent: "1.0.0"
        )
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.feedURL == URL(string: "https://example.com/releases.json"))
    }

    @Test func feedFlagWithoutValueLeavesFeedNil() {
        // `--feed`가 마지막 토큰이면 기존 동작은 무시하고 기본 피드(nil)를 쓴다.
        let result = DiagnoseArgs.parseCommon(["--feed"], defaultCurrent: "1.0.0")
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.feedURL == nil)
    }

    @Test func unparseableFeedFailsWithExactMessage() {
        // 미완성 IPv6 리터럴 등 구조적으로 깨진 문자열은 URL(string:)이 nil을
        // 반환한다(공백은 퍼센트 인코딩돼 통과하므로 nil 케이스가 아니다).
        let bad = "http://[bad"
        let result = DiagnoseArgs.parseCommon(["--feed", bad], defaultCurrent: "1.0.0")
        #expect(result == .failure("❌ --feed URL 파싱 실패: \(bad)"))
    }

    @Test func currentRawPreservesUserInputForDisplay() {
        // 진단 출력은 사용자가 입력한 원문을 그대로 보여줘야 한다(정규화 전).
        // "v1.2"는 SemanticVersion으로는 1.2.0이지만 표시는 "v1.2"여야 한다.
        let result = DiagnoseArgs.parseCommon(["--current", "v1.2"], defaultCurrent: "9.9.9")
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.currentVersion == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(opts.currentRaw == "v1.2")
    }

    @Test func currentRawFallsBackToDefaultRaw() {
        // --current가 없으면 currentRaw는 defaultCurrent 원문이어야 한다.
        let result = DiagnoseArgs.parseCommon([], defaultCurrent: "1.0")
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.currentRaw == "1.0")
        #expect(opts.currentVersion == SemanticVersion(major: 1, minor: 0, patch: 0))
    }

    @Test func currentFlagFollowedByAnotherFlagTreatsItAsValue() {
        // 가드는 인덱스만 보고 다음 토큰이 플래그인지 검사하지 않는다(기존 동작).
        // "--current --feed" 는 "--feed"를 버전으로 파싱하려다 실패한다.
        let result = DiagnoseArgs.parseCommon(["--current", "--feed", "x"], defaultCurrent: "1.0.0")
        #expect(result == .failure("❌ --current 버전 파싱 실패: --feed"))
    }

    @Test func duplicateCurrentFlagUsesFirst() {
        // firstIndex라 첫 번째 --current 값을 쓴다.
        let result = DiagnoseArgs.parseCommon(
            ["--current", "1.1.1", "--current", "2.2.2"],
            defaultCurrent: "9.9.9"
        )
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.currentVersion == SemanticVersion(major: 1, minor: 1, patch: 1))
    }

    @Test func currentAndFeedTogether() {
        let result = DiagnoseArgs.parseCommon(
            ["--download", "--current", "0.1.0", "--feed", "https://example.com/f.json", "--open"],
            defaultCurrent: "1.0.0"
        )
        guard case .ok(let opts) = result else {
            Issue.record("기대: .ok, 실제: \(result)")
            return
        }
        #expect(opts.currentVersion == SemanticVersion(major: 0, minor: 1, patch: 0))
        #expect(opts.feedURL == URL(string: "https://example.com/f.json"))
    }

    @Test func currentParseCheckedBeforeFeed() {
        // 현재 버전 파싱이 피드보다 먼저 검사된다(기존 코드 순서 보존).
        let result = DiagnoseArgs.parseCommon(
            ["--current", "bad", "--feed", "also bad"],
            defaultCurrent: "1.0.0"
        )
        #expect(result == .failure("❌ --current 버전 파싱 실패: bad"))
    }
}
