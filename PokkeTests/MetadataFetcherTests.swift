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

    func testOgDescriptionBecomesTheBody() {
        let html = """
        <html><head>
        <meta property="og:title" content="jack (@jack) on X">
        <meta property="og:description" content="just setting up my twttr">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://x.com/jack/status/20")

        XCTAssertEqual(meta.description, "just setting up my twttr")
    }

    func testFallsBackToMetaDescription() {
        let html = """
        <html><head>
        <meta name="description" content="記事の要約です">
        </head></html>
        """

        XCTAssertEqual(
            MetadataFetcher.parse(html: html, baseUrl: "https://example.com/").description,
            "記事の要約です"
        )
    }

    func testEmptyContentIsIgnored() {
        // 空文字を拾ってしまうと、後ろにある正しいタグを見に行かなくなる
        let html = """
        <html><head>
        <meta property="og:description" content="">
        <meta name="description" content="こちらが本文">
        </head></html>
        """

        XCTAssertEqual(
            MetadataFetcher.parse(html: html, baseUrl: "https://example.com/").description,
            "こちらが本文"
        )
    }

    // MARK: - YouTube

    func testYouTubeVideoIdIsReadFromEveryUrlShape() {
        XCTAssertEqual(
            MetadataFetcher.youTubeVideoId("https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            "dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            MetadataFetcher.youTubeVideoId("https://youtu.be/dQw4w9WgXcQ?si=abc"),
            "dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            MetadataFetcher.youTubeVideoId("https://www.youtube.com/shorts/abc123"),
            "abc123"
        )
        XCTAssertEqual(
            MetadataFetcher.youTubeVideoId("https://m.youtube.com/watch?v=abc123&t=10"),
            "abc123"
        )
    }

    func testNonVideoUrlsHaveNoYouTubeId() {
        XCTAssertNil(MetadataFetcher.youTubeVideoId("https://example.com/watch?v=abc"))
        XCTAssertNil(MetadataFetcher.youTubeVideoId("https://www.youtube.com/"))
        XCTAssertNil(MetadataFetcher.youTubeVideoId("https://www.youtube.com/@someone"))
    }

    func testYouTubeUrlsRouteToTheOEmbedEndpoint() {
        let endpoint = MetadataFetcher.oEmbedEndpoint("https://youtu.be/dQw4w9WgXcQ")

        XCTAssertEqual(endpoint?.hasPrefix("https://www.youtube.com/oembed?url="), true)
    }

    func testYouTubeOEmbedGivesTitleAndThumbnail() {
        let json = """
        {"title":"Never Gonna Give You Up","author_name":"Rick Astley",
         "provider_name":"YouTube",
         "thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"}
        """

        let meta = MetadataFetcher.parseOEmbed(json)

        XCTAssertEqual(meta?.title, "Never Gonna Give You Up")
        XCTAssertEqual(meta?.imageUrl, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        XCTAssertEqual(meta?.siteName, "YouTube")
    }

    // MARK: - X (Twitter)

    func testOnlyIndividualPostsCountAsTweets() {
        XCTAssertTrue(MetadataFetcher.isTweetUrl("https://x.com/jack/status/20"))
        XCTAssertTrue(MetadataFetcher.isTweetUrl("https://twitter.com/jack/status/20?s=20"))
        XCTAssertTrue(MetadataFetcher.isTweetUrl("https://mobile.twitter.com/jack/statuses/20"))
        // プロフィールやタイムラインはoEmbedの対象外
        XCTAssertFalse(MetadataFetcher.isTweetUrl("https://x.com/jack"))
        XCTAssertFalse(MetadataFetcher.isTweetUrl("https://x.com/home"))
        XCTAssertFalse(MetadataFetcher.isTweetUrl("https://example.com/a/status/20"))
    }

    func testTweetOEmbedGivesBodyAndAuthor() {
        // 実際の publish.twitter.com のレスポンス形（title/thumbnailは返ってこない）
        let json = """
        {"url":"https://x.com/jack/status/20","author_name":"jack",
         "provider_name":"Twitter",
         "html":"<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">just setting up my twttr</p>&mdash; jack (@jack) <a href=\\"https://x.com/jack/status/20\\">March 21, 2006</a></blockquote>"}
        """

        let meta = MetadataFetcher.parseOEmbed(json)

        XCTAssertEqual(meta?.description, "just setting up my twttr")
        XCTAssertEqual(meta?.title, "jack / Twitter")
    }

    func testTweetTextTurnsBrIntoNewlineAndDropsTags() {
        let html = "<blockquote><p>1行目<br>2行目 <a href=\"x\">リンク</a></p></blockquote>"

        XCTAssertEqual(MetadataFetcher.tweetText(html), "1行目\n2行目 リンク")
    }

    func testHtmlFillsInWhatOEmbedIsMissing() {
        // Xのoembedはサムネイルを返さないので、og:imageで埋める必要がある
        let oEmbed = MetadataFetcher.Metadata(
            title: "jack / X",
            siteName: "X",
            description: "just setting up my twttr"
        )
        let html = MetadataFetcher.Metadata(
            title: "jack (@jack) on X",
            imageUrl: "https://pbs.twimg.com/profile.jpg",
            description: "別の説明"
        )

        let merged = MetadataFetcher.preferring(oEmbed, html)

        // oEmbed側が優先される
        XCTAssertEqual(merged?.title, "jack / X")
        XCTAssertEqual(merged?.description, "just setting up my twttr")
        // 欠けていた項目だけHTMLから
        XCTAssertEqual(merged?.imageUrl, "https://pbs.twimg.com/profile.jpg")
    }

    func testPreferringPassesThroughWhenOneSideIsNil() {
        let meta = MetadataFetcher.Metadata(title: "a")

        XCTAssertEqual(MetadataFetcher.preferring(meta, nil), meta)
        XCTAssertEqual(MetadataFetcher.preferring(nil, meta), meta)
        XCTAssertNil(MetadataFetcher.preferring(nil, nil))
    }

    // MARK: - og:image が無いページ

    /// og:image が無ければ twitter:image を使う
    func testFallsBackToTwitterImage() {
        let html = """
        <html><head>
        <meta property="og:title" content="記事タイトル">
        <meta name="twitter:image" content="https://example.com/card.jpg">
        </head></html>
        """
        XCTAssertEqual(
            MetadataFetcher.parse(html: html, baseUrl: "https://example.com/a").imageUrl,
            "https://example.com/card.jpg"
        )
    }

    /// Amazonの主画像は元画像のURLで拾う
    func testProductImagePrefersTheOriginal() {
        let html = """
        <html><body>
        <img src="https://m.media-amazon.com/images/I/315s._SY445_.jpg"
             data-old-hires="https://m.media-amazon.com/images/I/7141._SL1500_.jpg"
             id="landingImage"
             data-a-dynamic-image="{&quot;https://m.media-amazon.com/images/I/7141._SY342_.jpg&quot;:[342,235]}">
        </body></html>
        """
        XCTAssertEqual(
            MetadataFetcher.productImage(html),
            "https://m.media-amazon.com/images/I/7141._SL1500_.jpg"
        )
    }

    /// 元画像が無ければ表示候補のうち最大を採る
    func testProductImageFallsBackToTheLargestCandidate() {
        let html = """
        <img id="imgBlkFront" src="https://m.media-amazon.com/images/I/a._SY100_.jpg"
             data-a-dynamic-image="{&quot;https://m.media-amazon.com/images/I/a._SY342_.jpg&quot;:[342,235],\
        &quot;https://m.media-amazon.com/images/I/a._SY522_.jpg&quot;:[522,359]}">
        """
        XCTAssertEqual(
            MetadataFetcher.productImage(html),
            "https://m.media-amazon.com/images/I/a._SY522_.jpg"
        )
    }

    /// 主画像はidで場所を決めてから読む（おすすめ商品の画像を掴まない）
    func testProductImageIsAnchoredToTheMainImageId() {
        let html = """
        <img src="https://example.com/sponsored.jpg" data-old-hires="https://example.com/other.jpg">
        <img id="landingImage" src="https://example.com/main.jpg">
        """
        XCTAssertEqual(MetadataFetcher.productImage(html), "https://example.com/main.jpg")
    }

    /// 商品ページでなければ本文から画像は拾わない
    func testNoProductImageOnOrdinaryPages() {
        XCTAssertNil(MetadataFetcher.productImage("<html><body><img src=\"https://example.com/p.jpg\"></body></html>"))
    }

    /// bodyにog情報を置くページ（YouTubeのコミュニティ投稿）でも読める
    func testOgTagsInBodyAreRead() {
        let html = """
        <html><head><title>YouTube</title></head><body>
        <title>チャンネル名 さんからの投稿</title>
        <meta property="og:title" content="チャンネル名 さんからの投稿">
        <meta property="og:image" content="https://yt3.ggpht.com/abc=s1600">
        </body></html>
        """
        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://www.youtube.com/post/Ugkx")
        XCTAssertEqual(meta.title, "チャンネル名 さんからの投稿")
        XCTAssertEqual(meta.imageUrl, "https://yt3.ggpht.com/abc=s1600")
    }

    // MARK: - User-Agent

    func testMetaServicesGetTheCrawlerUserAgent() {
        // ブラウザUAだとog:タグが1つも返ってこないため
        for url in [
            "https://www.instagram.com/p/abc/",
            "https://instagram.com/someone/",
            "https://www.facebook.com/x/posts/1",
            "https://www.threads.net/@someone/post/1",
        ] {
            XCTAssertTrue(MetadataFetcher.userAgentFor(url).hasPrefix("facebookexternalhit"), url)
        }
    }

    func testEverythingElseGetsTheBrowserUserAgent() {
        for url in [
            "https://x.com/jack/status/20",
            "https://www.youtube.com/watch?v=abc",
            "https://example.com/",
            // ドメイン末尾が一致するだけの別サイトに引っかからないこと
            "https://notinstagram.com/p/abc/",
            "https://instagram.com.evil.example/p/abc/",
        ] {
            XCTAssertTrue(MetadataFetcher.userAgentFor(url).hasPrefix("Mozilla/"), url)
        }
    }

    // MARK: - Instagram

    func testInstagramOgTagsAreReadableWithCharacterReferences() {
        // 実際のレスポンスは @ が &#064; になっている
        let html = """
        <html><head>
        <meta property="og:title" content="Instagram (&#064;instagram) &#x2022; Instagram photos and videos">
        <meta property="og:description" content="686M Followers - See Instagram photos and videos">
        <meta property="og:image" content="https://scontent.cdninstagram.com/v/t51.jpg?a=1&amp;b=2">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://www.instagram.com/instagram/")

        XCTAssertEqual(meta.title, "Instagram (@instagram) • Instagram photos and videos")
        XCTAssertEqual(meta.imageUrl, "https://scontent.cdninstagram.com/v/t51.jpg?a=1&b=2")
        XCTAssertEqual(meta.description?.hasPrefix("686M Followers"), true)
    }

    func testLikeCountsAreStrippedFromInstagramCaptions() {
        XCTAssertEqual(
            MetadataFetcher.stripSocialStats(
                "July 24, 2026、1,857 likes, 16 comments - soya_manga: \"チョコエッグ\""
            ),
            "チョコエッグ"
        )
        XCTAssertEqual(
            MetadataFetcher.stripSocialStats(
                "1,857 likes, 16 comments - soya_manga on July 24, 2026: \"caption text\"."
            ),
            "caption text"
        )
        // 複数行のキャプションもそのまま残る
        XCTAssertEqual(
            MetadataFetcher.stripSocialStats("5 likes, 1 comment - who: \"1行目\n2行目\""),
            "1行目\n2行目"
        )
    }

    func testDescriptionsWithoutStatsAreUntouched() {
        let plain = "記事のリード文です。いいねとは関係ありません。"
        XCTAssertEqual(MetadataFetcher.stripSocialStats(plain), plain)
        let tweet = "just setting up my twttr"
        XCTAssertEqual(MetadataFetcher.stripSocialStats(tweet), tweet)
    }

    func testInstagramPostBodyIsReadable() {
        // 実際のレスポンスの形（数値文字参照でエンコードされている）
        let html = """
        <html><head>
        <title>Instagram</title>
        <meta property="og:site_name" content="Instagram">
        <meta property="og:title" content="&#x66fd;&#x5c71;&#x4e00;&#x5bff; - Instagram: &quot;&#x30c1;&#x30e7;&#x30b3;&#x30a8;&#x30c3;&#x30b0;&quot;">
        <meta property="og:description" content="July 24, 2026&#x3001;1,857 likes, 16 comments - soya_manga: &quot;&#x30c1;&#x30e7;&#x30b3;&#x30a8;&#x30c3;&#x30b0;&quot;">
        </head></html>
        """

        let meta = MetadataFetcher.parse(html: html, baseUrl: "https://www.instagram.com/p/DbMlkSWGBaw/")

        XCTAssertEqual(meta.title, "曽山一寿 - Instagram: \"チョコエッグ\"")
        XCTAssertEqual(meta.description, "チョコエッグ")
    }

    func testTitlesThatAreJustTheServiceNameAreRejected() {
        // ログインが必要なInstagramの投稿では <title>Instagram</title> だけが返る。
        // これを使うと一覧で「Instagram」が並んで見分けが付かなくなる
        let html = "<html><head><title>Instagram</title></head></html>"
        XCTAssertNil(MetadataFetcher.parse(html: html, baseUrl: "https://www.instagram.com/p/abc/").title)

        XCTAssertTrue(MetadataFetcher.isJustSiteName("Instagram", siteName: nil, baseUrl: "https://www.instagram.com/p/a/"))
        XCTAssertTrue(MetadataFetcher.isJustSiteName("  youtube  ", siteName: nil, baseUrl: "https://www.youtube.com/watch?v=a"))
        XCTAssertTrue(MetadataFetcher.isJustSiteName("Example Site", siteName: "Example Site", baseUrl: "https://example.com/a"))
        XCTAssertTrue(MetadataFetcher.isJustSiteName("example.com", siteName: nil, baseUrl: "https://example.com/a"))
    }

    func testMeaningfulTitlesAreKept() {
        XCTAssertFalse(
            MetadataFetcher.isJustSiteName(
                "Instagram (@instagram) • Instagram photos and videos",
                siteName: "Instagram",
                baseUrl: "https://www.instagram.com/instagram/"
            )
        )
        let html = "<html><head><title>読書 - Wikipedia</title></head></html>"
        XCTAssertEqual(
            MetadataFetcher.parse(html: html, baseUrl: "https://ja.wikipedia.org/wiki/x").title,
            "読書 - Wikipedia"
        )
    }

    func testEmptyOEmbedResponsesAreNil() {
        XCTAssertNil(MetadataFetcher.parseOEmbed(#"{"version":"1.0"}"#))
        XCTAssertNil(MetadataFetcher.parseOEmbed("not json"))
    }
}
