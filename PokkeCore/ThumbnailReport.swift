import Foundation

/// 「このサイトのサムネイルが出ない」をGoogleフォームで知らせるための組み立て。
///
/// 既定で送るのはホストとURLの“形”だけで、URLそのものは含めない。
/// サムネイルが取れない原因は投稿単位ではなくホストとURLの種類で決まる
/// （MetadataFetcher の crawlerUaHosts や oEmbedEndpoint がその粒度で
/// 分岐している）ので、直すのにどの投稿かまでは要らない。
/// 保存したリンクはその人の興味そのものなので、要らないものは既定で送らない。
///
/// 送信自体はブラウザで開いたフォーム上で利用者が押す。アプリから直接POSTすると
/// 何が送られたのか本人に見えなくなるため、その形は採っていない。
enum ThumbnailReport {

    /// 送信先のGoogleフォーム。Android版 `data/ThumbnailReport.kt` と同じフォーム・同じentry番号
    enum Form {
        static let formId = "1FAIpQLScZy_pFOPb16wFXYxGIt__5nZLMPyJfk_fT1JkQGXZ3bcQapg"
        static let entryHost = "entry.361314032"
        static let entryDiagnostics = "entry.648216872"
        static let entryFullUrl = "entry.1179300262"

        // 「補足（任意）」は entry.155052730 だが、あえて事前入力しない。
        // 何か書いてあると読むだけで済ませてしまい、自由記述が集まらなくなる

        /// 未設定のまま報告ボタンだけ出ると、押しても何も起きないので導線ごと隠す
        static var isConfigured: Bool {
            !formId.isEmpty && !entryHost.isEmpty && !entryDiagnostics.isEmpty
        }
    }

    /// URLの経路を表す短い語。これだけは伏せずに残す。
    ///
    /// `/p/`（Instagramの投稿）と `/reel/` では取得のされ方が違うので、
    /// ここが消えると報告を受けても何のURLだったのか分からなくなる。
    /// 逆にここに無いものは利用者名にも投稿IDにもなり得るので、一律で伏せる。
    private static let routeWords: Set<String> = [
        "p", "reel", "reels", "tv", "story", "stories", "status", "statuses",
        "i", "web", "watch", "shorts", "embed", "live", "clip", "clips",
        "playlist", "channel", "c", "user", "users", "u", "profile",
        "post", "posts", "note", "notes", "n", "item", "items", "entry",
        "article", "articles", "a", "s", "t", "r", "comment", "comments",
        "wiki", "video", "videos", "photo", "photos", "image", "images",
        "gallery", "blog", "news", "event", "events", "list", "lists",
        "question", "questions", "share", "media", "threads", "topic",
        "detail", "view", "page", "pages", "search", "tag", "tags",
        "en", "ja", "ko", "jp",
    ]

    /// URLから、個人が辿れる部分を落とした“形”を作る。
    ///
    /// 例: `https://x.com/someone/status/1234?s=20` → `x.com/{id}/status/{n}?s={v}`
    ///
    /// クエリは値だけ伏せてキーは残す。YouTubeの `?v=` のように、
    /// どのキーが付いているかで取得経路が変わることがあるため。
    static func shapeOf(_ urlString: String) -> String {
        guard let components = URLComponents(string: urlString),
              let rawHost = components.host else { return "(invalid url)" }
        let host = (rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost).lowercased()
        let path = components.path
            .split(separator: "/")
            .filter { !$0.isEmpty }
            .map { maskSegment(String($0)) }
            .joined(separator: "/")
        let query = (components.percentEncodedQuery ?? "")
            .split(separator: "&")
            .filter { !$0.isEmpty }
            .map { String($0.split(separator: "=", maxSplits: 1)[0]) + "={v}" }
            .joined(separator: "&")
        var result = host
        if !path.isEmpty { result += "/" + path }
        if !query.isEmpty { result += "?" + query }
        return result
    }

    /// 経路を表す語だけ残し、それ以外は伏せる。利用者名も投稿IDも残さない
    private static func maskSegment(_ segment: String) -> String {
        let lower = segment.lowercased()
        if routeWords.contains(lower) { return lower }
        if !segment.isEmpty, segment.allSatisfy(\.isNumber) { return "{n}" }
        // 拡張子は取得のされ方に効くので残す（.html と .pdf では結果が違う）
        if let dotIndex = segment.lastIndex(of: "."), dotIndex != segment.startIndex {
            let ext = segment[segment.index(after: dotIndex)...]
            if !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return "{id}.\(ext.lowercased())"
            }
        }
        return "{id}"
    }

    /// 開発者が読む診断情報。
    ///
    /// 中身は端末の言語に関わらず固定の英語にしている。届いた要望を横断して読むのは
    /// 開発者なので、言語ごとに文面が変わると突き合わせられなくなる。
    /// この文字列は送信前にそのまま利用者へ見せるので、隠している情報は無い。
    static func diagnosticsOf(item: StashItem, appVersion: String, language: String) -> String {
        var lines: [String] = []
        lines.append("url: \(shapeOf(item.url))")
        lines.append("title: \(present(!item.title.trimmingCharacters(in: .whitespaces).isEmpty))")
        lines.append("image: \(present(item.imageUrl != nil))")
        lines.append("note: \(present(item.description != nil))")
        lines.append("site: \(item.siteName ?? "-")")
        lines.append("ua: \(uaLabel(item.url))")
        lines.append("oembed: \(present(MetadataFetcher.oEmbedEndpoint(item.url) != nil))")
        lines.append("app: \(appVersion) / \(language)")
        return lines.joined(separator: "\n")
    }

    private static func present(_ value: Bool) -> String { value ? "ok" : "missing" }

    private static func uaLabel(_ url: String) -> String {
        MetadataFetcher.userAgentFor(url).hasPrefix("facebookexternalhit") ? "crawler" : "browser"
    }

    /// 事前入力したフォームのURL。ブラウザで開き、送信は利用者自身が押す。
    ///
    /// `fullUrl` は本人が明示的に選んだときだけ渡す。
    static func prefillUrl(host: String, diagnostics: String, fullUrl: String?) -> String {
        var url = "https://docs.google.com/forms/d/e/\(Form.formId)/viewform?usp=pp_url"
        url += "&\(Form.entryHost)=\(encode(host))"
        url += "&\(Form.entryDiagnostics)=\(encode(diagnostics))"
        if let fullUrl, !fullUrl.isEmpty, !Form.entryFullUrl.isEmpty {
            url += "&\(Form.entryFullUrl)=\(encode(fullUrl))"
        }
        return url
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
