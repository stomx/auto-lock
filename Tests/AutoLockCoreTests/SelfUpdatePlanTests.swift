import Testing
import Foundation
@testable import AutoLockCore

/// `SelfUpdatePlan` is the pure swap-plan data. Its only behavior is the
/// positional argument vector ($1..$3) the helper reads; the script *text* that
/// consumes those args lives in `AutoLockKit.SelfUpdateScript`, tested there.
@Suite struct SelfUpdatePlanTests {

    private func plan(
        pid: Int32 = 4242,
        staging: String = "/Applications/.AutoLockUpdate-v1.2.3/AutoLock.app",
        target: String = "/Applications/AutoLock.app"
    ) -> SelfUpdatePlan {
        SelfUpdatePlan(parentPID: pid, stagingAppPath: staging, targetAppPath: target)
    }

    // 인자 벡터는 [pid, staging, target] 순서로 정확히 전달된다.
    // (스크립트의 $1=pid $2=staging $3=target 계약과 일치 — SelfUpdateScriptTests가 교차고정)
    @Test func argumentsAreInOrder() {
        let p = plan()
        #expect(p.arguments == [
            "4242",
            "/Applications/.AutoLockUpdate-v1.2.3/AutoLock.app",
            "/Applications/AutoLock.app",
        ])
    }
}
