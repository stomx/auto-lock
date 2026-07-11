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
        #expect(s.contains("/bin/mv \"$STAGING\" \"$TARGET\"")) // 원자적 교체
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

    // 단계 순서: 부모 대기 → 백업 → 원자적 교체 → quarantine 제거 → 재실행.
    // contains()만으로는 순서가 뒤바뀌어도 통과하므로 위치로 검증한다.
    @Test func stepsAreInSafeOrder() {
        let s = SelfUpdateScript.text(for: plan())
        let wait = index(of: "kill -0", in: s)
        let backup = index(of: "/bin/mv \"$TARGET\" \"$BACKUP\"", in: s)
        let replace = index(of: "/bin/mv \"$STAGING\" \"$TARGET\"", in: s)
        let relaunch = index(of: "--post-update-marker", in: s)
        #expect(wait != nil && backup != nil && replace != nil && relaunch != nil)
        if let wait, let backup, let replace, let relaunch {
            #expect(wait < backup)
            #expect(backup < replace)
            #expect(replace < relaunch)
        }
    }

    @Test func failedReplaceAndFailedHealthBothRestoreBackup() {
        let s = SelfUpdateScript.text(for: plan())
        #expect(s.contains("if ! /bin/mv \"$STAGING\" \"$TARGET\""))
        #expect(s.components(separatedBy: "/bin/mv \"$BACKUP\" \"$TARGET\"").count == 3)
        #expect(s.contains("kill \"$NEW_PID\""))
        #expect(s.contains("[ -f \"$MARKER\" ]"))
    }

    @Test func helperAtomicallyReplacesAndKeepsHealthyApp() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = root.appendingPathComponent("AutoLock.app", isDirectory: true)
        let stagingDir = root.appendingPathComponent(".staging", isDirectory: true)
        let staged = stagingDir.appendingPathComponent("AutoLock.app", isDirectory: true)
        let newExecutable = staged.appendingPathComponent("Contents/MacOS/AutoLock")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try "old".write(to: target.appendingPathComponent("payload"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: newExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\ntouch \"$2\"\nsleep 0.2\n".write(to: newExecutable, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: newExecutable.path)
        try "new".write(to: staged.appendingPathComponent("payload"), atomically: true, encoding: .utf8)

        let runtimePlan = SelfUpdatePlan(
            parentPID: 999_999,
            stagingAppPath: staged.path,
            targetAppPath: target.path
        )
        let script = root.appendingPathComponent("helper.sh")
        try SelfUpdateScript.text(for: runtimePlan).write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + runtimePlan.arguments
        try process.run()
        process.waitUntilExit()
        defer { try? fm.removeItem(at: root) }

        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: target.appendingPathComponent("payload"), encoding: .utf8) == "new")
        #expect(!fm.fileExists(atPath: "\(target.path).autolock-backup"))
    }
}
