import Testing
import Foundation
@testable import AutoLockKit
import AutoLockCore

/// `Sha256SumsParser` is the format adapter for `SHA256SUMS.txt` text (shasum
/// `<hex>  <filename>` lines). These tests pin the text-format parsing; the
/// fail-closed verification *policy* is tested by `ChecksumVerifierTests` in Core.
@Suite struct Sha256SumsParserTests {
    private let sums = """
    504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c  AutoLock-0.3.1-arm64.dmg
    a81556a8b7af119d2f7efa62bf57211f7adc7764508d5b8c427fb764c2b78824  AutoLock-0.3.1-arm64.zip
    """

    @Test func findsHashForFile() {
        let h = Sha256SumsParser.expectedSHA256(in: sums, for: "AutoLock-0.3.1-arm64.dmg")
        #expect(h == "504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c")
    }

    @Test func nilForMissingFile() {
        #expect(Sha256SumsParser.expectedSHA256(in: sums, for: "nope.dmg") == nil)
    }

    // 탭/다중 공백 구분도 허용한다(shasum은 두 칸이지만 관대하게 파싱).
    @Test func tolerantOfWhitespaceVariants() {
        let tabbed = "abc123\tAutoLock.dmg"
        #expect(Sha256SumsParser.expectedSHA256(in: tabbed, for: "AutoLock.dmg") == "abc123")
    }

    // 형식이 깨진 줄(토큰 1개)은 건너뛴다.
    @Test func skipsMalformedLines() {
        let messy = """
        garbage-line-without-filename
        504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c  AutoLock-0.3.1-arm64.dmg
        """
        #expect(Sha256SumsParser.expectedSHA256(in: messy, for: "AutoLock-0.3.1-arm64.dmg")
            == "504b5105e7b30bc2ba2641569addd1c69194f831e60b910a37f6a097a55fa23c")
    }
}
