import Testing
import Foundation
@testable import AutoLockCore

/// `SemanticVersion` parses and compares `major.minor.patch` strings (with an
/// optional leading `v`) so the updater can decide whether a GitHub release is
/// newer than the running build. Pure value type, no I/O.
@Suite struct SemanticVersionTests {

    // 1. 평범한 "0.3.1" 파싱.
    @Test func parsesPlain() {
        let v = SemanticVersion("0.3.1")
        #expect(v == SemanticVersion(major: 0, minor: 3, patch: 1))
    }

    // 2. 선행 "v" 허용 (GitHub 태그는 보통 "v0.3.1").
    @Test func parsesLeadingV() {
        #expect(SemanticVersion("v0.3.1") == SemanticVersion(major: 0, minor: 3, patch: 1))
        #expect(SemanticVersion("V1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    // 3. patch 생략 시 0으로 보정 ("1.2" → 1.2.0).
    @Test func missingPatchDefaultsToZero() {
        #expect(SemanticVersion("1.2") == SemanticVersion(major: 1, minor: 2, patch: 0))
    }

    // 4. 잘못된 형식은 nil.
    @Test func rejectsGarbage() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("abc") == nil)
        #expect(SemanticVersion("1.x.0") == nil)
        #expect(SemanticVersion("v") == nil)
    }

    // 5. 비교: patch/minor/major 순서.
    @Test func ordersByComponents() {
        #expect(SemanticVersion("0.3.1")! < SemanticVersion("0.3.2")!)
        #expect(SemanticVersion("0.3.9")! < SemanticVersion("0.4.0")!)
        #expect(SemanticVersion("0.9.9")! < SemanticVersion("1.0.0")!)
        #expect(SemanticVersion("1.0.0")! > SemanticVersion("0.9.9")!)
    }

    // 6. 동일 버전은 같음(>가 아님).
    @Test func equalVersionsAreEqual() {
        #expect(SemanticVersion("0.3.1")! == SemanticVersion("v0.3.1")!)
        #expect(!(SemanticVersion("0.3.1")! < SemanticVersion("0.3.1")!))
    }

    // 7. 공백 트림.
    @Test func trimsWhitespace() {
        #expect(SemanticVersion("  v0.3.1\n") == SemanticVersion(major: 0, minor: 3, patch: 1))
    }
}
