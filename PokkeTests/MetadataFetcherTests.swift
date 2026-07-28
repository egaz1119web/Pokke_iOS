import XCTest

final class MetadataFetcherTests: XCTestCase {

    func testShortTitlesAreUnchanged() {
        XCTAssertEqual(MetadataFetcher.cleanTitle("お任せCOOK"), "お任せCOOK")
    }

    func testNewlinesAndRunsOfSpacesCollapse() {
        XCTAssertEqual(MetadataFetcher.cleanTitle("行1\n\n行2   \t行3"), "行1 行2 行3")
    }

    func testLongTitlesAreTruncatedWithEllipsis() {
        let cleaned = MetadataFetcher.cleanTitle(String(repeating: "あ", count: 300))

        XCTAssertLessThanOrEqual(cleaned.utf16.count, 101, "長さは101以下であるべき")
        XCTAssertTrue(cleaned.hasSuffix("…"), "末尾は省略記号")
    }

    func testLongTitlesBreakAtASentenceBoundary() {
        let caption = "今日のごはん。" + String(repeating: "とても美味しかったです。", count: 20)
        let cleaned = MetadataFetcher.cleanTitle(caption)

        XCTAssertTrue(cleaned.hasSuffix("…"))
        // 句点直後で切れており、語の途中で終わっていない
        XCTAssertTrue(cleaned.dropLast().hasSuffix("。"))
    }

    func testParseTruncatesLongOgTitle() {
        let body = String(repeating: "とても長いキャプション本文です。", count: 30)
        let html = """
        <html><head>
        <meta property="og:title" content="\(body)">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://www.instagram.com/p/xxx/")

        XCTAssertLessThanOrEqual(meta.title?.utf16.count ?? 0, 101)
        XCTAssertEqual(meta.title?.hasSuffix("…"), true)
    }

    func testHexNumericCharacterReferencesAreDecoded() {
        // Instagramのog:titleは日本語が &#x304a; のような16進数値文字参照でエンコードされている
        let html = """
        <html><head>
        <meta property="og:title" content="&#x304a;&#x4efb;&#x305b;COOK">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://www.instagram.com/p/xxx/")

        XCTAssertEqual(meta.title, "お任せCOOK")
    }

    func testOgImageAmpIsDecodedBeforeResolving() {
        // 署名付きCDN URLは &amp; でクエリ区切りがエスケープされていることが多く、
        // 展開せず結合すると署名が壊れて画像が読み込めなくなる
        let html = """
        <html><head>
        <meta property="og:image" content="https://scontent.cdninstagram.com/img.jpg?_nc_ht=x&amp;oh=abc&amp;oe=def">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://www.instagram.com/p/xxx/")

        XCTAssertEqual(
            meta.imageUrl,
            "https://scontent.cdninstagram.com/img.jpg?_nc_ht=x&oh=abc&oe=def"
        )
    }

    func testDecimalAndNamedEntitiesAreDecoded() {
        let html = """
        <html><head>
        <meta property="og:title" content="A &#38; B &#x27;quoted&#x27;">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://example.com/")

        XCTAssertEqual(meta.title, "A & B 'quoted'")
    }

    func testFallsBackToTitleTagAndResolvesRelativeImage() {
        let html = """
        <html><head><title>
        ページの
        タイトル</title>
        <meta content="/og.png" property="og:image">
        <meta property="og:site_name" content="Example">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://example.com/a/b")

        XCTAssertEqual(meta.title, "ページの タイトル")
        XCTAssertEqual(meta.siteName, "Example")
        XCTAssertEqual(meta.imageUrl, "https://example.com/og.png")
    }
}
