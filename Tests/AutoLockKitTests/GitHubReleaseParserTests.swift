import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

/// `GitHubReleaseParser.parse` is the format adapter: it decodes a GitHub
/// `releases/latest` JSON body into `RemoteReleaseAsset`s and delegates the
/// installable-artifact choice to the pure `ReleaseInfo.select`. These tests
/// pin the JSON-key knowledge (tag_name / assets / browser_download_url) and
/// the malformed-input handling that belongs to the adapter — the selection
/// rules themselves are covered by `ReleaseInfoSelectTests` in Core.
@Suite struct GitHubReleaseParserTests {

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

    // JSON 키를 올바로 디코딩해 select 규칙으로 넘긴다.
    @Test func decodesGitHubKeysIntoReleaseInfo() throws {
        let r = try #require(GitHubReleaseParser.parse(fixture()))
        #expect(r.tag == "v0.3.2")
        #expect(r.dmgURL.absoluteString == "https://example.com/AutoLock-0.3.2-arm64.dmg")
        #expect(r.zipFileName == "AutoLock-0.3.2-arm64.zip")
        #expect(r.checksumsURL?.absoluteString == "https://example.com/SHA256SUMS.txt")
    }

    // 깨진 JSON은 nil.
    @Test func nilOnBrokenJSON() {
        #expect(GitHubReleaseParser.parse(Data("not json".utf8)) == nil)
    }

    // tag가 버전이 아니면(select 규칙) nil.
    @Test func nilWhenTagNotVersion() {
        #expect(GitHubReleaseParser.parse(fixture(tag: "nightly")) == nil)
    }

    // dmg asset이 없으면(select 규칙) nil.
    @Test func nilWhenNoDmgAsset() {
        let json = """
        { "tag_name": "v0.3.2", "assets": [
          { "name": "AutoLock-0.3.2-arm64.zip", "browser_download_url": "https://e.com/a.zip" }
        ] }
        """.data(using: .utf8)!
        #expect(GitHubReleaseParser.parse(json) == nil)
    }

    // download URL이 깨진 zip asset은 zipURL=nil로만 반영되고, dmg가 정상이면
    // 릴리스 자체는 유효하다(DMG 폴백 경로).
    @Test func brokenZipUrlLeavesReleaseValidWithoutZip() throws {
        let json = """
        { "tag_name": "v0.3.2", "assets": [
          { "name": "AutoLock-0.3.2-arm64.dmg", "browser_download_url": "https://e.com/a.dmg" },
          { "name": "AutoLock-0.3.2-arm64.zip", "browser_download_url": "http://[broken" }
        ] }
        """.data(using: .utf8)!
        let r = try #require(GitHubReleaseParser.parse(json))
        #expect(r.dmgFileName == "AutoLock-0.3.2-arm64.dmg")
        #expect(r.zipURL == nil)   // 깨진 zip URL → 자가교체 불가, dmg 폴백
    }

    // fail-closed: 이름으로 고른 dmg의 URL이 깨졌으면 다른 dmg로 폴백하지 않고
    // 전체 릴리스를 거부한다(깨진 자산을 미리 버리지 않고 select에 그대로 넘김).
    @Test func brokenChosenDmgUrlRejectsRelease() {
        let json = """
        { "tag_name": "v0.3.2", "assets": [
          { "name": "AutoLock-0.3.2-arm64.dmg", "browser_download_url": "http://[broken" },
          { "name": "AutoLock-0.3.2-universal.dmg", "browser_download_url": "https://e.com/u.dmg" }
        ] }
        """.data(using: .utf8)!
        #expect(GitHubReleaseParser.parse(json) == nil)
    }
}
