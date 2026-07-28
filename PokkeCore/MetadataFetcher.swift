import Foundation

/// ページのタイトル・OGP画像などを軽量に取得する（HTML先頭のみ読む）
enum MetadataFetcher {

    struct Metadata: Equatable {
        var title: String?
        var siteName: String?
        var imageUrl: String?
    }

    private static let maxBytes = 256 * 1024
    private static let maxTitleLength = 100

    /// リダイレクトは URLSession に任せる。HTMLは先頭 maxBytes だけ読んで打ち切る
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    static func fetch(_ urlString: String) async -> Metadata? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone) Pokke/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                // 中断しないとコネクションが開いたままになる
                bytes.task.cancel()
                return nil
            }
            var data = Data()
            data.reserveCapacity(maxBytes)
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes { break }
            }
            bytes.task.cancel()

            // 文字コード宣言はここでは見ず、UTF-8として読めない分は捨てて解釈する。
            // 必要なのは og: メタタグと <title> だけなので実害は小さい
            let html = String(decoding: data, as: UTF8.self)
            let base = http.url ?? url
            return parse(html: html, baseUrl: base.absoluteString)
        } catch {
            return nil
        }
    }

    /// HTML断片からog:title / og:site_name / og:image / <title> を抜き出す
    static func parse(html: String, baseUrl: String) -> Metadata {
        let ogTitle = metaContent(html, property: "og:title")
        let docTitle = firstMatch(
            in: html,
            pattern: "<title[^>]*>(.*?)</title>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        let image = metaContent(html, property: "og:image").flatMap { raw -> String? in
            // 署名付きURLの &amp; など、クエリ文字列中のエンティティも展開してから解決する
            let resolved = unescape(raw)
            return URL(string: resolved, relativeTo: URL(string: baseUrl))?.absoluteString
        }

        let title = (ogTitle ?? docTitle)
            .map(unescape)
            .map(cleanTitle)
            .flatMap { $0.isBlank ? nil : $0 }

        return Metadata(
            title: title,
            siteName: metaContent(html, property: "og:site_name").map(unescape),
            imageUrl: image
        )
    }

    /// タイトルの改行・連続空白を1つのスペースに畳み込み、長すぎる場合は省略する。
    /// Instagramなどはog:titleに投稿本文全文が入るため、そのままだと極端に長くなる。
    static func cleanTitle(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Kotlin版と同じく「UTF-16のコード単位数」で判定する（両OSで同じ位置で切るため）
        if collapsed.utf16.count <= maxTitleLength { return collapsed }

        let cut = collapsed.safePrefix(maxTitleLength)
        // できるだけ語・文の区切りで切る。句読点は残し、スペースは捨てる
        let breakChars = CharacterSet(charactersIn: " 、。，．!?！？")
        let base: String
        if let range = cut.rangeOfCharacter(from: breakChars, options: .backwards),
           cut.distance(from: cut.startIndex, to: range.lowerBound) >= maxTitleLength / 2 {
            base = cut[range] == " " ? String(cut[..<range.lowerBound]) : String(cut[...range.lowerBound])
        } else {
            base = cut
        }
        return base.trimmingTrailingWhitespace() + "…"
    }

    private static func metaContent(_ html: String, property: String) -> String? {
        // property/content の並び順どちらにも対応
        let p = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(p)[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(p)[\"']",
        ]
        for pattern in patterns {
            if let found = firstMatch(in: html, pattern: pattern, options: [.caseInsensitive]) {
                return found.trimmingCharacters(in: .whitespacesAndNewlines)
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

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
