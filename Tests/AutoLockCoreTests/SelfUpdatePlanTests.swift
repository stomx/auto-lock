import Testing
import Foundation
@testable import AutoLockCore

/// `SelfUpdatePlan` builds the detached swap script + argument vector. Pure —
/// no process is spawned here; we only assert the generated text/args.
@Suite struct SelfUpdatePlanTests {

    private func plan(
        pid: Int32 = 4242,
        staging: String = "/Applications/.AutoLockUpdate-v1.2.3/AutoLock.app",
        target: String = "/Applications/AutoLock.app"
    ) -> SelfUpdatePlan {
        SelfUpdatePlan(parentPID: pid, stagingAppPath: staging, targetAppPath: target)
    }

    // 인자 벡터는 [pid, staging, target] 순서로 정확히 전달된다.
    @Test func argumentsAreInOrder() {
        let p = plan()
        #expect(p.arguments == [
            "4242",
            "/Applications/.AutoLockUpdate-v1.2.3/AutoLock.app",
            "/Applications/AutoLock.app",
        ])
    }

    // 스크립트는 sh shebang으로 시작하고 핵심 단계를 모두 포함한다.
    @Test func scriptHasAllSteps() {
        let s = plan().scriptText
        #expect(s.hasPrefix("#!/bin/sh"))
        #expect(s.contains("kill -0"))                       // 부모 종료 대기
        #expect(s.contains("/usr/bin/ditto"))                // 번들 교체
        #expect(s.contains("xattr -dr com.apple.quarantine"))// Gatekeeper 재경고 방지
        #expect(s.contains("/usr/bin/open"))                 // 재실행
    }

    // 스크립트는 경로를 "$VAR"로 인용해 공백/특수문자 경로에도 안전하다.
    @Test func scriptQuotesExpansions() {
        let s = plan().scriptText
        #expect(s.contains("\"$TARGET\""))
        #expect(s.contains("\"$STAGING\""))
        #expect(s.contains("\"$PARENT\""))
    }

    // shellQuote는 작은따옴표를 '\'' 시퀀스로 이스케이프해 탈출을 막는다.
    @Test func shellQuoteEscapesSingleQuote() {
        #expect(SelfUpdatePlan.shellQuote("/Users/a b/App.app") == "'/Users/a b/App.app'")
        #expect(SelfUpdatePlan.shellQuote("it's") == "'it'\\''s'")
    }
}
