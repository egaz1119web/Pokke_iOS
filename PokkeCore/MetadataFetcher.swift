import Foundation

/// ページのタイトル・OGP画像などを軽量に取得する（HTML先頭のみ読む）。
///
/// Android版 `data/MetadataFetcher.kt` と同じ判定・同じ整形を行う。
/// 片方だけ直すと、同じリンクでも端末によってタイトルや本文が変わってしまう。
enum MetadataFetcher {

    struct Metadata: Equatable {
        var title: String?
        var siteName: String?
        var imageUrl: String?
        var description: String?

        init(title: String? = nil, siteName: String? = nil, imageUrl: String? = nil, description: String? = nil) {
            self.title = title
            self.siteName = siteName
            self.imageUrl = imageUrl
            self.description = description
        }

        /// 一覧に必要な項目が揃っているか。揃っていなければHTMLからの取得で補う。
        ///
        /// 本文（description）は含めない。YouTubeはog:タグがHTMLの約690KB地点にあり、
        /// 概要文のためだけに毎回それを落とすのは通信量に見合わないため、
        /// oEmbedでタイトルとサムネイルが取れた時点で打ち切る。
        var isComplete: Bool { title != nil && imageUrl != nil }
    }

    /// HTMLを読む上限。og:タグは通常30KB以内に収まるが、`</head>` を見つけたら
    /// その時点で読むのをやめるので、実際の通信量はほとんどのサイトで数十KBに収まる。
    private static let maxBytes = 1024 * 1024
    private static let maxJsonBytes = 64 * 1024
    private static let maxRedirects = 5
    private static let maxTitleLength = 100
    private static let maxDescriptionLength = 600

    /// デスクトップChromeのUA。
    ///
    /// - 独自UAだと YouTube・X が og: タグを一切返さない
    /// - モバイルUAだと YouTube が og:description を返さず、
    ///   全動画共通の定型文が meta description に入ってしまう
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    /// Metaのサービスはリンクプレビュー用のog:タグを、自社クローラのUAにしか返さない。
    /// ブラウザのUAで取りに行くとJavaScript前提の空のシェルHTMLが返り、
    /// og:タグが1つも無いためタイトルもサムネイルも取れなかった。
    private static let crawlerUserAgent = "facebookexternalhit/1.1"

    private static let crawlerUaHosts: Set<String> = [
        "instagram.com", "facebook.com", "threads.net", "threads.com",
    ]

    /// そのURLに使うUA。og:タグを返してくれる方を選ぶ
    static func userAgentFor(_ url: String) -> String {
        guard var host = URLComponents(string: url)?.host?.lowercased() else { return userAgent }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        let matches = crawlerUaHosts.contains(host) || crawlerUaHosts.contains { host.hasSuffix(".\($0)") }
        return matches ? crawlerUserAgent : userAgent
    }

    /// リダイレクトは自前で辿る。ホストが変わるとUAも変える必要があるため、
    /// URLSessionの自動追従には任せられない（短縮URL → Instagram など）
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config, delegate: NoRedirect.shared, delegateQueue: nil)
    }()

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        static let shared = NoRedirect()

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // nil を返すと 3xx のレスポンスがそのまま返る。Location は自分で見る
            completionHandler(nil)
        }
    }

    static func fetch(_ url: String) async -> Metadata? {
        var oEmbed: Metadata?
        if let endpoint = oEmbedEndpoint(url) { oEmbed = await fetchOEmbed(endpoint) }
        // oEmbedだけで揃うことは少ない（Xはサムネイルを返さない、YouTubeは概要を返さない）。
        // 足りない項目をHTMLのog:タグで補う
        if let oEmbed, oEmbed.isComplete { return oEmbed }
        return preferring(oEmbed, await fetchHtml(url))
    }

    /// [primary] を優先し、欠けている項目だけ [fallback] から補う
    static func preferring(_ primary: Metadata?, _ fallback: Metadata?) -> Metadata? {
        guard let primary else { return fallback }
        guard let fallback else { return primary }
        return Metadata(
            title: primary.title ?? fallback.title,
            siteName: primary.siteName ?? fallback.siteName,
            imageUrl: primary.imageUrl ?? fallback.imageUrl,
            description: primary.description ?? fallback.description
        )
    }

    // MARK: - 取得

    private static func fetchHtml(_ startUrl: String) async -> Metadata? {
        guard let (data, finalUrl) = await load(
            startUrl,
            accept: "text/html",
            limit: maxBytes,
            stopAtHeadEnd: true
        ) else { return nil }
        // 文字コード宣言はここでは見ず、UTF-8として読めない分は捨てて解釈する。
        // 必要なのは og: メタタグと <title> だけなので実害は小さい
        return parse(html: String(decoding: data, as: UTF8.self), baseUrl: finalUrl)
    }

    private static func fetchOEmbed(_ endpoint: String) async -> Metadata? {
        guard let (data, _) = await load(
            endpoint,
            accept: "application/json",
            limit: maxJsonBytes,
            stopAtHeadEnd: false
        ) else { return nil }
        return parseOEmbed(String(decoding: data, as: UTF8.self))
    }

    /// リダイレクトを自前で辿りつつ本文の先頭だけ読む。
    /// `stopAtHeadEnd` が真なら `</head>` を見つけた時点で打ち切る。
    private static func load(
        _ startUrl: String,
        accept: String,
        limit: Int,
        stopAtHeadEnd: Bool
    ) async -> (Data, String)? {
        var current = startUrl
        for _ in 0..<maxRedirects {
            guard let url = URL(string: current) else { return nil }
            var request = URLRequest(url: url)
            request.setValue(userAgentFor(current), forHTTPHeaderField: "User-Agent")
            request.setValue(accept, forHTTPHeaderField: "Accept")
            request.setValue("ja,en;q=0.8", forHTTPHeaderField: "Accept-Language")

            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    bytes.task.cancel()
                    return nil
                }
                if (300..<400).contains(http.statusCode) {
                    bytes.task.cancel()
                    guard let location = http.value(forHTTPHeaderField: "Location"),
                          let next = URL(string: location, relativeTo: url)?.absoluteString
                    else { return nil }
                    current = next
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    bytes.task.cancel()
                    return nil
                }
                var data = Data()
                data.reserveCapacity(min(limit, 64 * 1024))
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= limit { break }
                    // og:タグは head 内にしか無いので、body を丸ごと落とす必要がない
                    if stopAtHeadEnd, byte == UInt8(ascii: ">"), data.hasHeadEndSuffix { break }
                }
                bytes.task.cancel()
                return (data, http.url?.absoluteString ?? current)
            } catch {
                return nil
            }
        }
        return nil
    }

    // MARK: - oEmbed

    /// oEmbedで取れるサービスのエンドポイントURL。対象外ならnil。
    /// どちらも認証不要の公開エンドポイント。
    static func oEmbedEndpoint(_ url: String) -> String? {
        let encoded = url.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.*")
        ) ?? url
        if youTubeVideoId(url) != nil {
            return "https://www.youtube.com/oembed?url=\(encoded)&format=json"
        }
        if isTweetUrl(url) {
            return "https://publish.twitter.com/oembed?url=\(encoded)&omit_script=1&dnt=true"
        }
        return nil
    }

    /// oEmbedのJSONからメタデータを組み立てる。
    /// X（Twitter）はtitle/thumbnailを返さないので、html内のツイート本文を本文として使い、
    /// 投稿者名をタイトルに充てる。
    static func parseOEmbed(_ json: String) -> Metadata? {
        guard let data = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        let provider = (o["provider_name"] as? String)?.nilIfBlank
        let author = (o["author_name"] as? String)?.nilIfBlank
        let embedText = (o["html"] as? String)?.nilIfBlank.flatMap(tweetText)

        var title = (o["title"] as? String)?.nilIfBlank
        if title == nil, let author {
            title = embedText != nil
                ? author + (provider.map { " / \($0)" } ?? "")
                : author
        }

        let result = Metadata(
            title: title.map { cleanTitle(unescape($0)) },
            siteName: provider ?? author,
            imageUrl: (o["thumbnail_url"] as? String)?.nilIfBlank,
            description: embedText.map { clip($0, limit: maxDescriptionLength) }
        )
        guard result.title != nil || result.imageUrl != nil || result.description != nil else { return nil }
        return result
    }

    /// oEmbedの blockquote HTML から本文（<p>…</p>）だけを取り出す
    static func tweetText(_ html: String) -> String? {
        guard let inner = firstMatch(
            in: html,
            pattern: "<p[^>]*>(.*?)</p>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let text = unescape(
            inner
                .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        )
        .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// YouTubeの動画ID。watch/shorts/embed/youtu.be に対応。対象外ならnil
    static func youTubeVideoId(_ url: String) -> String? {
        guard let components = URLComponents(string: url), var host = components.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if host.hasPrefix("m.") { host = String(host.dropFirst(2)) }
        let path = components.path

        let id: String?
        if host == "youtu.be" {
            id = path.drop { $0 == "/" }.split(separator: "/").first.map(String.init)
        } else if host != "youtube.com" && host != "music.youtube.com" {
            return nil
        } else if path.hasPrefix("/watch") {
            id = components.queryItems?.first { $0.name == "v" }?.value
        } else if let prefix = ["/shorts/", "/embed/", "/live/"].first(where: { path.hasPrefix($0) }) {
            id = path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
        } else {
            id = nil
        }
        // 動画IDは英数字と - _ のみ
        guard let id, !id.isEmpty,
              id.allSatisfy({ $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "-" || $0 == "_" })
        else { return nil }
        return id
    }

    /// x.com / twitter.com の個別ポストURLか
    static func isTweetUrl(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), var host = components.host?.lowercased() else { return false }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if host.hasPrefix("mobile.") { host = String(host.dropFirst(7)) }
        guard host == "x.com" || host == "twitter.com" else { return false }
        return components.path.range(
            of: "^/[^/]+/status(?:es)?/\\d+",
            options: .regularExpression
        ) != nil
    }

    // MARK: - HTML

    /// HTML断片からog:title / og:site_name / og:image / og:description / <title> を抜き出す
    static func parse(html: String, baseUrl: String) -> Metadata {
        let ogTitle = metaContent(html, property: "og:title")
        let docTitle = firstMatch(
            in: html,
            pattern: "<title[^>]*>(.*?)</title>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let image = metaContent(html, property: "og:image").flatMap { raw -> String? in
            // 署名付きURLの &amp; など、クエリ文字列中のエンティティも展開してから解決する
            URL(string: unescape(raw), relativeTo: URL(string: baseUrl))?.absoluteString
        }

        var description: String?
        if let raw = metaContent(html, property: "og:description") ?? metaContent(html, property: "description") {
            let normalized = unescape(raw)
                .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                description = clip(stripSocialStats(normalized), limit: maxDescriptionLength)
            }
        }

        let siteName = metaContent(html, property: "og:site_name").map(unescape)

        var title: String?
        if let raw = ogTitle ?? docTitle {
            let cleaned = cleanTitle(unescape(raw))
            if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isJustSiteName(cleaned, siteName: siteName, baseUrl: baseUrl) {
                title = cleaned
            }
        }

        return Metadata(title: title, siteName: siteName, imageUrl: image, description: description)
    }

    /// Instagramのog:descriptionに付く定型の前置きを落として、キャプション本文だけにする。
    ///
    /// 実際に返ってくる形:
    ///   `July 24, 2026、1,857 likes, 16 comments - soya_manga: "チョコエッグ"`
    ///
    /// 一覧では2行しか出ないので、前置きに埋まると本文が全く見えない。
    /// 該当しない文字列はそのまま返す。
    static func stripSocialStats(_ description: String) -> String {
        guard let caption = firstMatch(
            in: description,
            pattern: "likes?,\\s*[\\d,]+\\s*comments?\\s*-\\s*[^:]*:\\s*[\"“”](.+?)[\"“”]\\s*\\.?\\s*$",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty else { return description }
        return caption
    }

    /// タイトルがサービス名だけで、どのページか分からない状態か。
    ///
    /// ログインが必要なページなどでは `<title>Instagram</title>` のような
    /// 中身の無いタイトルだけが返る。これを採用すると一覧で同じ名前が並んで
    /// 見分けが付かなくなるので、採用せずURLを表示に回す。
    static func isJustSiteName(_ title: String, siteName: String?, baseUrl: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        if let siteName, t == siteName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() { return true }
        guard var host = URLComponents(string: baseUrl)?.host else { return false }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if t == host.lowercased() { return true }
        return t == DomainGrouping.domainLabel(host: host).lowercased()
    }

    /// タイトルの改行・連続空白を1つのスペースに畳み込み、長すぎる場合は省略する。
    /// Instagramなどはog:titleに投稿本文全文が入るため、そのままだと極端に長くなる。
    static func cleanTitle(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clip(collapsed, limit: maxTitleLength)
    }

    /// 指定長を超えたら、できるだけ語・文の区切りで切って「…」を付ける。
    /// Kotlin版と同じく「UTF-16のコード単位数」で判定する（両OSで同じ位置で切るため）
    private static func clip(_ text: String, limit: Int) -> String {
        if text.utf16.count <= limit { return text }
        let cut = text.safePrefix(limit) as NSString
        // 句読点は残し、スペースは捨てる
        let breakChars = CharacterSet(charactersIn: " \n、。，．!?！？")
        let found = cut.rangeOfCharacter(from: breakChars, options: .backwards)
        let base: String
        if found.location != NSNotFound, found.location >= limit / 2 {
            let isSpace = cut.substring(with: found).first?.isWhitespace ?? false
            base = isSpace
                ? cut.substring(to: found.location)
                : cut.substring(to: found.location + found.length)
        } else {
            base = cut as String
        }
        return base.trimmingTrailingWhitespace() + "…"
    }

    private static func metaContent(_ html: String, property: String) -> String? {
        // property/content の並び順どちらにも対応
        let p = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(p)[\"'][^>]+content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+(?:property|name)=[\"']\(p)[\"']",
        ]
        for pattern in patterns {
            if let found = firstMatch(in: html, pattern: pattern, options: [.caseInsensitive])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !found.isEmpty {
                return found
            }
        }
        return nil
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static let numericEntity = try? NSRegularExpression(
        pattern: "&#x([0-9a-fA-F]+);|&#([0-9]+);"
    )

    private static func unescape(_ s: String) -> String {
        var out = s
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        guard let regex = numericEntity else { return out }
        let ns = out as NSString
        let matches = regex.matches(in: out, range: NSRange(location: 0, length: ns.length))
        // 後ろから置換して、前方のレンジがずれないようにする
        for match in matches.reversed() {
            let hex = match.range(at: 1).location != NSNotFound
                ? UInt32(ns.substring(with: match.range(at: 1)), radix: 16) : nil
            let dec = match.range(at: 2).location != NSNotFound
                ? UInt32(ns.substring(with: match.range(at: 2)), radix: 10) : nil
            guard let codePoint = hex ?? dec, let scalar = Unicode.Scalar(codePoint) else { continue }
            out = (out as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }
        return out
    }
}

private extension Data {
    /// 末尾が `</head>` か（`</HEAD>` のような大文字表記も拾う）
    var hasHeadEndSuffix: Bool {
        let needle = Array("</head>".utf8)
        guard count >= needle.count else { return false }
        let tail = suffix(needle.count)
        return zip(tail, needle).allSatisfy { lhs, rhs in
            (lhs >= 65 && lhs <= 90 ? lhs + 32 : lhs) == rhs
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    /// サロゲートペア（絵文字など）を途中で割らずに先頭n（UTF-16コード単位）を取る
    func safePrefix(_ n: Int) -> String {
        let ns = self as NSString
        if ns.length <= n { return self }
        // 境界がサロゲートペアの真ん中なら1つ手前まで下げる
        let end = ns.rangeOfComposedCharacterSequence(at: n).location
        return ns.substring(to: min(end, n))
    }

    func trimmingTrailingWhitespace() -> String {
        var s = self
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return s
    }
}
