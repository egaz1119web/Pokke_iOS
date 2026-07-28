import XCTest

@MainActor
final class NormalizeUrlTests: XCTestCase {

    func testExtractsUrlFromSharedText() {
        XCTAssertEqual(
            StashRepository.normalizeUrl("この記事いいよ https://example.com/a よかったら"),
            "https://example.com/a"
        )
    }

    func testHttpIsUpgradedToHttps() {
        XCTAssertEqual(StashRepository.normalizeUrl("http://example.com/"), "https://example.com/")
    }

    func testTrailingPunctuationIsTrimmed() {
        XCTAssertEqual(StashRepository.normalizeUrl("https://example.com/a。"), "https://example.com/a")
        XCTAssertEqual(StashRepository.normalizeUrl("（https://example.com/a）"), "https://example.com/a）")
        XCTAssertEqual(StashRepository.normalizeUrl("https://example.com/a」"), "https://example.com/a")
    }

    func testNonUrlTextIsRejected() {
        XCTAssertNil(StashRepository.normalizeUrl("ただのテキスト"))
        XCTAssertNil(StashRepository.normalizeUrl(""))
        XCTAssertNil(StashRepository.normalizeUrl("ftp://example.com/a"))
    }

    func testFallbackTitleDropsTheScheme() {
        XCTAssertEqual(StashRepository.displayFallbackTitle("https://example.com/a"), "example.com/a")
        XCTAssertEqual(StashRepository.displayFallbackTitle("http://example.com/a"), "example.com/a")
    }
}
