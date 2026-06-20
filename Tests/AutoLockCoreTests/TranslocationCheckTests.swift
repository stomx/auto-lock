import Testing
import Foundation
@testable import AutoLockCore

/// `InstallLocation.classify` decides whether the app can replace its own
/// bundle. Pure — the writability probe is injected, so we drive it directly.
@Suite struct TranslocationCheckTests {

    // 정상 /Applications 경로 + 쓰기가능 → replaceable.
    @Test func writableAppsPathIsReplaceable() {
        let v = InstallLocation.classify(bundlePath: "/Applications/AutoLock.app") { _ in true }
        #expect(v == .replaceable)
    }

    // translocation 경로는 쓰기가능을 보고해도 무조건 translocated.
    @Test func translocatedPathDetected() {
        let path = "/private/var/folders/xy/AppTranslocation/ABC-123/d/AutoLock.app"
        let v = InstallLocation.classify(bundlePath: path) { _ in true }
        #expect(v == .translocated)
    }

    // 실 경로지만 쓰기 불가 → notWritable.
    @Test func realButNotWritable() {
        let v = InstallLocation.classify(bundlePath: "/Applications/AutoLock.app") { _ in false }
        #expect(v == .notWritable)
    }

    // isTranslocated 순수 판정.
    @Test func isTranslocatedHeuristic() {
        #expect(InstallLocation.isTranslocated(path: "/x/AppTranslocation/y/App.app"))
        #expect(!InstallLocation.isTranslocated(path: "/Applications/App.app"))
        #expect(!InstallLocation.isTranslocated(path: "/Users/me/Applications/App.app"))
    }

    // translocation 판정이 쓰기검사보다 우선한다(쓰기가능해도 translocated).
    @Test func translocationTakesPrecedence() {
        let path = "/var/AppTranslocation/r/AutoLock.app"
        #expect(InstallLocation.classify(bundlePath: path) { _ in true } == .translocated)
    }
}
