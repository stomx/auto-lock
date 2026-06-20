import Testing
import Foundation
@testable import AutoLockCore

/// `ReleaseInfo.parse` turns a GitHub `releases/latest` JSON payload into the
/// few fields the updater needs: the version tag, the arm64 DMG download URL,
/// and the SHA256SUMS URL. Pure — operates on `Data`, no network.
@Suite struct ReleaseInfoTests {

    // 실제 stomx/auto-lock 릴리스 응답을 축약한 픽스처.
    private func fixture(tag: String = "v0.3.2") -> Data {
        """
        {
          "tag_name": "\(tag)",
          "assets": [
            { "name": "AutoLock-0.3.2-arm64.dmg",
              "browser_download_url": "https://example.com/AutoLock-0.3.2-arm64.dmg" },
            { "name": "AutoLock-0.3.2-arm64.zip",
              "browser_download_url": "https://example.com/AutoLock-0.3.2-arm64.zip" },
            { "name": "SHA256SUMS.txt",
              "browser_download_url": "https://example.com/SHA256SUMS.txt" }
          ]
        }
        """.data(using: .utf8)!
    }

    // 1. tag + dmg + checksums URL을 모두 뽑는다.
    @Test func parsesAllFields() throws {
        let r = try #require(ReleaseInfo.parse(fixture()))
        #expect(r.version == SemanticVersion("0.3.2"))
        #expect(r.tag == "v0.3.2")
        #expect(r.dmgURL.absoluteString == "https://example.com/AutoLock-0.3.2-arm64.dmg")
        #expect(r.dmgFileName == "AutoLock-0.3.2-arm64.dmg")
        #expect(r.checksumsURL?.absoluteString == "https://example.com/SHA256SUMS.txt")
    }

    // 2. zip이 아니라 dmg를 고른다(arm64 dmg 우선).
    @Test func picksDmgNotZip() throws {
        let r = try #require(ReleaseInfo.parse(fixture()))
        #expect(r.dmgFileName.hasSuffix(".dmg"))
    }

    // 2b. arm64/x64 dmg가 함께 있으면 arm64를 고른다(첫 dmg가 x64여도).
    @Test func prefersArm64Dmg() throws {
        let json = """
        { "tag_name": "v0.3.2", "assets": [
          { "name": "AutoLock-0.3.2-x86_64.dmg", "browser_download_url": "https://e.com/x64.dmg" },
          { "name": "AutoLock-0.3.2-arm64.dmg", "browser_download_url": "https://e.com/arm64.dmg" }
        ] }
        """.data(using: .utf8)!
        let r = try #require(ReleaseInfo.parse(json))
        #expect(r.dmgFileName == "AutoLock-0.3.2-arm64.dmg")
    }

    // 2c. arm64가 없으면 그냥 첫 dmg로 폴백.
    @Test func fallsBackToAnyDmg() throws {
        let json = """
        { "tag_name": "v0.3.2", "assets": [
          { "name": "AutoLock-0.3.2-universal.dmg", "browser_download_url": "https://e.com/u.dmg" }
        ] }
        """.data(using: .utf8)!
        let r = try #require(ReleaseInfo.parse(json))
        #expect(r.dmgFileName == "AutoLock-0.3.2-universal.dmg")
    }

    // 3. dmg asset이 없으면 nil(설치 가능한 산출물 없음).
    @Test func nilWhenNoDmg() {
        let json = """
        { "tag_name": "v0.3.2", "assets": [
          { "name": "AutoLock-0.3.2-arm64.zip", "browser_download_url": "https://e.com/a.zip" }
        ] }
        """.data(using: .utf8)!
        #expect(ReleaseInfo.parse(json) == nil)
    }

    // 4. tag가 파싱 불가능한 버전이면 nil.
    @Test func nilWhenTagNotVersion() {
        #expect(ReleaseInfo.parse(fixture(tag: "nightly")) == nil)
    }

    // 5. 체크섬 asset이 없어도 dmg가 있으면 파싱은 되고 checksumsURL만 nil.
    @Test func checksumsOptional() throws {
        let json = """
        { "tag_name": "v0.3.2", "assets": [
          { "name": "AutoLock-0.3.2-arm64.dmg", "browser_download_url": "https://e.com/a.dmg" }
        ] }
        """.data(using: .utf8)!
        let r = try #require(ReleaseInfo.parse(json))
        #expect(r.checksumsURL == nil)
    }

    // 6. 깨진 JSON은 nil.
    @Test func nilOnBrokenJSON() {
        #expect(ReleaseInfo.parse(Data("not json".utf8)) == nil)
    }
}

/// `UpdateCheck.decide` compares the running version against the latest release.
@Suite struct UpdateCheckTests {

    private func release(_ tag: String) -> ReleaseInfo {
        ReleaseInfo(
            tag: tag,
            version: SemanticVersion(tag)!,
            dmgURL: URL(string: "https://e.com/a.dmg")!,
            dmgFileName: "a.dmg",
            checksumsURL: nil
        )
    }

    // 최신 > 현재 → 업데이트 가능.
    @Test func newerIsAvailable() {
        let d = UpdateCheck.decide(current: SemanticVersion("0.3.1")!, latest: release("v0.3.2"))
        #expect(d == .updateAvailable(release("v0.3.2")))
    }

    // 같음 → 최신.
    @Test func sameIsUpToDate() {
        let d = UpdateCheck.decide(current: SemanticVersion("0.3.1")!, latest: release("v0.3.1"))
        #expect(d == .upToDate)
    }

    // 최신 < 현재(로컬이 더 최신/개발빌드) → 최신 취급(다운그레이드 안내 안 함).
    @Test func olderRemoteIsUpToDate() {
        let d = UpdateCheck.decide(current: SemanticVersion("0.4.0")!, latest: release("v0.3.1"))
        #expect(d == .upToDate)
    }
}

/// `ChecksumVerifier` extracts a file's SHA256 from a `SHA256SUMS.txt` body
/// (`<hex>  <filename>` per line) so a downloaded DMG can be verified.
@Suite struct ChecksumVerifierTests {
    private let sums = """
    504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c  AutoLock-0.3.1-arm64.dmg
    a81556a8b7af119d2f7efa62bf57211f7adc7764508d5b8c427fb764c2b78824  AutoLock-0.3.1-arm64.zip
    """

    @Test func findsHashForFile() {
        let h = ChecksumVerifier.expectedSHA256(in: sums, for: "AutoLock-0.3.1-arm64.dmg")
        #expect(h == "504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c")
    }

    @Test func nilForMissingFile() {
        #expect(ChecksumVerifier.expectedSHA256(in: sums, for: "nope.dmg") == nil)
    }

    @Test func matchesAreCaseInsensitive() {
        // expected(대문자)와 actual(소문자)이 표기만 달라도 같은 해시로 본다.
        #expect(ChecksumVerifier.matches(expected: "AA11BB22", actual: "aa11bb22"))
        #expect(!ChecksumVerifier.matches(expected: "AA11BB22", actual: "ff00"))
    }

    // verify(...) 는 fail-closed: 항목이 있고 일치할 때만 .verified.
    @Test func verifyMatch() {
        let r = ChecksumVerifier.verify(
            sums: sums, fileName: "AutoLock-0.3.1-arm64.dmg",
            actual: "504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c")
        #expect(r == .verified)
    }

    @Test func verifyMismatch() {
        let r = ChecksumVerifier.verify(sums: sums, fileName: "AutoLock-0.3.1-arm64.dmg", actual: "deadbeef")
        #expect(r == .mismatch)
    }

    // 항목 누락은 통과가 아니라 실패(fail-closed). 손상/변조 릴리스를 조용히 허용 금지.
    @Test func verifyEntryMissingFails() {
        let r = ChecksumVerifier.verify(sums: sums, fileName: "ghost.dmg", actual: "abc")
        #expect(r == .entryMissing)
    }
}
