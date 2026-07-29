import XCTest

final class ThumbnailReportTests: XCTestCase {

    // ---- shapeOf -----------------------------------------------------

    func testKeepsTheRouteWordButHidesThePostId() {
        XCTAssertEqual(
            ThumbnailReport.shapeOf("https://www.instagram.com/p/C8xYz1AbCdE/"),
            "instagram.com/p/{id}"
        )
    }

    func testHidesTheAccountNameInAPostUrl() {
        // 利用者名は経路語に無いので伏せる。どの投稿かだけでなく誰の投稿かも残さない
        XCTAssertEqual(
            ThumbnailReport.shapeOf("https://x.com/someone/status/1234567890"),
            "x.com/{id}/status/{n}"
        )
    }

    func testKeepsQueryKeysButHidesTheirValues() {
        XCTAssertEqual(
            ThumbnailReport.shapeOf("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42"),
            "youtube.com/watch?v={v}&t={v}"
        )
    }

    func testHidesDateAndSlugInAnArticleUrl() {
        XCTAssertEqual(
            ThumbnailReport.shapeOf("https://example.com/2026/07/my-secret-diary-entry"),
            "example.com/{n}/{n}/{id}"
        )
    }

    func testKeepsTheFileExtensionBecauseItChangesHowThePageIsFetched() {
        XCTAssertEqual(
            ThumbnailReport.shapeOf("https://example.com/report-2026.pdf"),
            "example.com/{id}.pdf"
        )
    }

    func testHostOnlyUrlHasNoTrailingSlash() {
        XCTAssertEqual(ThumbnailReport.shapeOf("https://example.com/"), "example.com")
    }

    func testBrokenUrlDoesNotThrow() {
        XCTAssertEqual(ThumbnailReport.shapeOf("not a url at all"), "(invalid url)")
    }

    func testShapeNeverLeaksTheOriginalPathText() {
        let shape = ThumbnailReport.shapeOf("https://www.instagram.com/reel/AbCdEfGhIjK/")
        XCTAssertFalse(shape.contains("AbCdEfGhIjK"))
        XCTAssertTrue(shape.hasPrefix("instagram.com/reel/"))
    }

    // ---- diagnosticsOf -------------------------------------------------

    private func item(_ url: String, imageUrl: String? = nil, description: String? = nil) -> StashItem {
        StashItem(
            id: "1",
            url: url,
            title: "タイトル",
            siteName: "Instagram",
            imageUrl: imageUrl,
            description: description,
            savedAt: 0
        )
    }

    func testDiagnosticsReportTheMissingImageAndTheCrawlerUa() {
        let text = ThumbnailReport.diagnosticsOf(
            item: item("https://www.instagram.com/p/C8xYz1AbCdE/"),
            appVersion: "1.2.3",
            language: "ja-JP"
        )
        XCTAssertTrue(text.contains("url: instagram.com/p/{id}"))
        XCTAssertTrue(text.contains("image: missing"))
        XCTAssertTrue(text.contains("title: ok"))
        XCTAssertTrue(text.contains("note: missing"))
        XCTAssertTrue(text.contains("ua: crawler"))
        XCTAssertTrue(text.contains("app: 1.2.3 / ja-JP"))
    }

    func testDiagnosticsNeverContainTheSavedUrlItself() {
        // 既定で完全なURLを送らないことが前提なので、診断情報側から漏れないことを固定する
        let url = "https://x.com/someone/status/1234567890"
        let text = ThumbnailReport.diagnosticsOf(item: item(url), appVersion: "1.2.3", language: "en-US")
        XCTAssertFalse(text.contains("someone"))
        XCTAssertFalse(text.contains("1234567890"))
        XCTAssertTrue(text.contains("oembed: ok"))
    }

    // ---- prefillUrl ------------------------------------------------------

    func testPrefillUrlOmitsTheFullLinkByDefault() {
        let url = ThumbnailReport.prefillUrl(host: "instagram.com", diagnostics: "url: instagram.com", fullUrl: nil)
        XCTAssertTrue(url.hasPrefix("https://docs.google.com/forms/d/e/\(ThumbnailReport.Form.formId)/viewform"))
        XCTAssertTrue(url.contains("\(ThumbnailReport.Form.entryHost)=instagram.com"))
        XCTAssertFalse(url.contains(ThumbnailReport.Form.entryFullUrl))
    }

    func testPrefillUrlIncludesTheFullLinkWhenOptedIn() {
        let url = ThumbnailReport.prefillUrl(
            host: "instagram.com",
            diagnostics: "url: instagram.com",
            fullUrl: "https://www.instagram.com/p/C8xYz1AbCdE/"
        )
        XCTAssertTrue(url.contains("\(ThumbnailReport.Form.entryFullUrl)="))
    }
}
