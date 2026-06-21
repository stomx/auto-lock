import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

/// `SelfUpdateScript.text` turns a pure `SelfUpdatePlan` into the detached
/// `/bin/sh` helper body. This is update mechanism, so it's tested in the Kit
/// layer. Paths arrive as positional args, so these tests also pin the
/// `$1=pid $2=staging $3=target` contract against `SelfUpdatePlan.arguments`.
@Suite struct SelfUpdateScriptTests {

    private func plan() -> SelfUpdatePlan {
        SelfUpdatePlan(
            parentPID: 4242,
            stagingAppPath: "/Applications/.AutoLockUpdate-v1.2.3/AutoLock.app",
            targetAppPath: "/Applications/AutoLock.app"
        )
    }

    /// Index of `needle` in `haystack`, or nil — for asserting step ordering.
    private func index(of needle: String, in haystack: String) -> String.Index? {
        haystack.range(of: needle)?.lowerBound
    }

    // 스크립트는 sh shebang으로 시작하고 핵심 단계를 모두 포함한다.
    @Test func scriptHasAllSteps() {
        let s = SelfUpdateScript.text(for: plan())
        #expect(s.hasPrefix("#!/bin/sh"))
        #expect(s.contains("kill -0"))                       // 부모 종료 대기
        #expect(s.contains("/usr/bin/ditto"))                // 번들 교체
        #expect(s.contains("xattr -dr com.apple.quarantine"))// Gatekeeper 재경고 방지
        #expect(s.contains("/usr/bin/open"))                 // 재실행
    }

    // 스크립트는 경로를 "$VAR"로 인용해 공백/특수문자 경로에도 안전하다.
    @Test func scriptQuotesExpansions() {
        let s = SelfUpdateScript.text(for: plan())
        #expect(s.contains("\"$TARGET\""))
        #expect(s.contains("\"$STAGING\""))
        #expect(s.contains("\"$PARENT\""))
    }

    // $1/$2/$3 → PARENT/STAGING/TARGET 매핑이 SelfUpdatePlan.arguments
    // 순서([pid, staging, target])와 일치한다. 한쪽이 어긋나면 이 테스트가 깨진다.
    @Test func positionalContractMatchesArguments() {
        let s = SelfUpdateScript.text(for: plan())
        // 스크립트가 가정하는 매핑.
        #expect(s.contains("PARENT=\"$1\""))
        #expect(s.contains("STAGING=\"$2\""))
        #expect(s.contains("TARGET=\"$3\""))
        // arguments는 그 $1/$2/$3 순서대로 pid/staging/target을 낸다.
        #expect(plan().arguments == [
            "4242",                                              // $1 = PARENT(pid)
            "/Applications/.AutoLockUpdate-v1.2.3/AutoLock.app", // $2 = STAGING
            "/Applications/AutoLock.app",                        // $3 = TARGET
        ])
    }

    // 단계 순서: 부모 대기 → (기존 제거 → 복사) → quarantine 제거 → 재실행.
    // contains()만으로는 순서가 뒤바뀌어도 통과하므로 위치로 검증한다.
    @Test func stepsAreInSafeOrder() {
        let s = SelfUpdateScript.text(for: plan())
        let wait = index(of: "kill -0", in: s)
        let remove = index(of: "rm -rf \"$TARGET\"", in: s)
        let copy = index(of: "/usr/bin/ditto", in: s)
        let relaunch = index(of: "/usr/bin/open", in: s)
        #expect(wait != nil && remove != nil && copy != nil && relaunch != nil)
        if let wait, let remove, let copy, let relaunch {
            #expect(wait < remove)     // 부모가 죽기 전 번들을 건드리면 안 됨
            #expect(remove < copy)     // 기존 제거 후 새 번들 복사
            #expect(copy < relaunch)   // 복사 완료 후 재실행
        }
    }

    // 파괴적 단계(rm/ditto)는 실패 시 즉시 중단(|| exit 1)해 반쪽 교체를 막는다.
    @Test func destructiveStepsFailClosed() {
        let s = SelfUpdateScript.text(for: plan())
        #expect(s.contains("rm -rf \"$TARGET\" || exit 1"))
        #expect(s.contains("/usr/bin/ditto \"$STAGING\" \"$TARGET\" || exit 1"))
    }
}
