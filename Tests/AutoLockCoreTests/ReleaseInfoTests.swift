import Testing
import Foundation
@testable import AutoLockCore

/// `ReleaseInfo.select` is the pure domain rule that picks the installable
/// artifacts from a release's already-decoded assets: prefer the arm64 dmg,
/// take the arm64 zip if present, find the checksums file. Format-neutral — it
/// never sees JSON (that's `GitHubReleaseParser` in AutoLockKit).
@Suite struct ReleaseInfoSelectTests {

    private func asset(_ name: String, _ url: String = "https://e.com/x") -> RemoteReleaseAsset {
        RemoteReleaseAsset(name: name, downloadURL: URL(string: url)!)
    }

    /// An asset the adapter couldn't give a usable URL (downloadURL == nil).
    private func brokenAsset(_ name: String) -> RemoteReleaseAsset {
        RemoteReleaseAsset(name: name, downloadURL: nil)
    }

    // 실제 릴리스 자산 구성을 축약한 픽스처.
    private func fixture(tag: String = "v0.3.2") -> (String, [RemoteReleaseAsset]) {
        (tag, [
            asset("AutoLock-0.3.2-arm64.dmg", "https://example.com/AutoLock-0.3.2-arm64.dmg"),
            asset("AutoLock-0.3.2-arm64.zip", "https://example.com/AutoLock-0.3.2-arm64.zip"),
            asset("SHA256SUMS.txt", "https://example.com/SHA256SUMS.txt"),
        ])
    }

    // 1. tag + dmg + zip + checksums URL을 모두 뽑는다.
    @Test func selectsAllFields() throws {
        let (tag, assets) = fixture()
        let r = try #require(ReleaseInfo.select(tag: tag, assets: assets))
        #expect(r.version == SemanticVersion("0.3.2"))
        #expect(r.tag == "v0.3.2")
        #expect(r.dmgURL.absoluteString == "https://example.com/AutoLock-0.3.2-arm64.dmg")
        #expect(r.dmgFileName == "AutoLock-0.3.2-arm64.dmg")
        #expect(r.checksumsURL?.absoluteString == "https://example.com/SHA256SUMS.txt")
        #expect(r.zipURL?.absoluteString == "https://example.com/AutoLock-0.3.2-arm64.zip")
        #expect(r.zipFileName == "AutoLock-0.3.2-arm64.zip")
    }

    // 1b. arm64 zip을 우선 추출(self-update용). arm64가 없으면 첫 zip 폴백.
    @Test func extractsArm64Zip() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-arm64.dmg"),
            asset("AutoLock-0.3.2-x86_64.zip"),
            asset("AutoLock-0.3.2-arm64.zip"),
        ]))
        #expect(r.zipFileName == "AutoLock-0.3.2-arm64.zip")
    }

    // 1c. zip이 없어도 dmg가 있으면 성공(하위호환). zip 필드는 nil.
    @Test func zipOptionalForBackwardCompat() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-arm64.dmg"),
        ]))
        #expect(r.zipURL == nil)
        #expect(r.zipFileName == nil)
    }

    // 2. zip이 아니라 dmg를 고른다(arm64 dmg 우선).
    @Test func picksDmgNotZip() throws {
        let (tag, assets) = fixture()
        let r = try #require(ReleaseInfo.select(tag: tag, assets: assets))
        #expect(r.dmgFileName.hasSuffix(".dmg"))
    }

    // 2b. arm64/x64 dmg가 함께 있으면 arm64를 고른다(첫 dmg가 x64여도).
    @Test func prefersArm64Dmg() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-x86_64.dmg"),
            asset("AutoLock-0.3.2-arm64.dmg"),
        ]))
        #expect(r.dmgFileName == "AutoLock-0.3.2-arm64.dmg")
    }

    // 2c. arm64가 없으면 그냥 첫 dmg로 폴백.
    @Test func fallsBackToAnyDmg() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-universal.dmg"),
        ]))
        #expect(r.dmgFileName == "AutoLock-0.3.2-universal.dmg")
    }

    // 3. dmg asset이 없으면 nil(설치 가능한 산출물 없음).
    @Test func nilWhenNoDmg() {
        #expect(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-arm64.zip"),
        ]) == nil)
    }

    // 4. tag가 파싱 불가능한 버전이면 nil.
    @Test func nilWhenTagNotVersion() {
        let (_, assets) = fixture()
        #expect(ReleaseInfo.select(tag: "nightly", assets: assets) == nil)
    }

    // 5. 체크섬 asset이 없어도 dmg가 있으면 성공하고 checksumsURL만 nil.
    @Test func checksumsOptional() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-arm64.dmg"),
        ]))
        #expect(r.checksumsURL == nil)
    }

    // 6. 자산이 비면 nil.
    @Test func nilWhenNoAssets() {
        #expect(ReleaseInfo.select(tag: "v0.3.2", assets: []) == nil)
    }

    // 7. fail-closed: 이름으로 고른 arm64 dmg의 URL이 깨졌으면, 다른 dmg가
    //    있더라도 폴백하지 않고 전체 릴리스를 거부한다(이름 우선 선택 → URL 검증).
    @Test func brokenChosenDmgUrlRejectsReleaseEvenWithFallback() {
        let r = ReleaseInfo.select(tag: "v0.3.2", assets: [
            brokenAsset("AutoLock-0.3.2-arm64.dmg"),   // 선택되지만 URL 없음
            asset("AutoLock-0.3.2-universal.dmg"),      // 폴백 후보지만 쓰지 않음
        ])
        #expect(r == nil)
    }

    // 8. fail-closed: arm64 zip URL이 깨졌으면 다른 아키텍처 zip으로 갈아타지
    //    않고 zipURL=nil(자가교체 불가 → DMG 폴백)로 둔다. dmg는 정상이라 릴리스 자체는 유효.
    @Test func brokenArm64ZipUrlDoesNotFallBackToOtherArch() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-arm64.dmg"),
            brokenAsset("AutoLock-0.3.2-arm64.zip"),    // 선택되지만 URL 없음
            asset("AutoLock-0.3.2-x86_64.zip"),         // 잘못된 아키텍처 — 쓰면 안 됨
        ]))
        #expect(r.zipURL == nil)
    }

    // 9. zipURL이 nil이면 zipFileName도 nil이어야 한다(쌍 일관성).
    //    이름만 남으면 Diagnostics가 "쓸 수 있는 ZIP이 있는 것처럼" 잘못 표시한다.
    @Test func zipFileNameNilWhenZipUrlBroken() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-arm64.dmg"),
            brokenAsset("AutoLock-0.3.2-arm64.zip"),
        ]))
        #expect(r.zipURL == nil)
        #expect(r.zipFileName == nil)   // 이름도 함께 비어야 함
    }

    // 10. checksums의 URL이 깨졌으면 checksumsURL=nil로만 반영되고, dmg가 정상이면
    //     릴리스 자체는 유효하다(체크섬 없는 릴리스와 동일하게 다운로드 단계에서 fail-closed).
    @Test func brokenChecksumsUrlLeavesReleaseValidWithoutChecksums() throws {
        let r = try #require(ReleaseInfo.select(tag: "v0.3.2", assets: [
            asset("AutoLock-0.3.2-arm64.dmg"),
            brokenAsset("SHA256SUMS.txt"),
        ]))
        #expect(r.checksumsURL == nil)
        #expect(r.dmgFileName == "AutoLock-0.3.2-arm64.dmg")
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

/// `ChecksumVerifier` is the pure verification *policy* — fail-closed,
/// case-insensitive — operating on an already-extracted expected hash. The
/// `SHA256SUMS.txt` text parsing is a Kit format adapter (`Sha256SumsParser`),
/// tested there.
@Suite struct ChecksumVerifierTests {
    private let hash = "504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c"

    @Test func matchesAreCaseInsensitive() {
        // expected(대문자)와 actual(소문자)이 표기만 달라도 같은 해시로 본다.
        #expect(ChecksumVerifier.matches(expected: "AA11BB22", actual: "aa11bb22"))
        #expect(!ChecksumVerifier.matches(expected: "AA11BB22", actual: "ff00"))
    }

    // verify(...) 는 fail-closed: expected가 있고 일치할 때만 .verified.
    @Test func verifyMatch() {
        #expect(ChecksumVerifier.verify(expected: hash, actual: hash) == .verified)
    }

    // 대소문자만 다른 경우도 일치로 본다.
    @Test func verifyMatchCaseInsensitive() {
        #expect(ChecksumVerifier.verify(expected: hash.uppercased(), actual: hash) == .verified)
    }

    @Test func verifyMismatch() {
        #expect(ChecksumVerifier.verify(expected: hash, actual: "deadbeef") == .mismatch)
    }

    // expected==nil(SHA256SUMS에 항목 없음)은 통과가 아니라 실패(fail-closed).
    // 손상/변조 릴리스를 조용히 허용 금지.
    @Test func verifyEntryMissingFails() {
        #expect(ChecksumVerifier.verify(expected: nil, actual: "abc") == .entryMissing)
    }
}
