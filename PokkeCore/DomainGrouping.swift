import Foundation

/// ドメイン別まとめの1グループ
struct DomainGroup: Identifiable {
    var label: String
    var items: [StashItem]

    var id: String { label }
}

/// 保存アイテムをドメイン（サービス）ごとにまとめるロジック。純関数で単体テスト対象。
/// 例: twitter.com / x.com → "Twitter"、youtu.be / youtube.com → "YouTube"
enum DomainGrouping {

    /// 主要サービスの表示名。サブドメインにも一致させる
    private static let brandByDomain: [String: String] = [
        "twitter.com": "Twitter",
        "x.com": "Twitter",
        "instagram.com": "Instagram",
        "youtube.com": "YouTube",
        "youtu.be": "YouTube",
        "facebook.com": "Facebook",
        "tiktok.com": "TikTok",
        "github.com": "GitHub",
        "note.com": "note",
        "qiita.com": "Qiita",
        "zenn.dev": "Zenn",
        "wikipedia.org": "Wikipedia",
        "amazon.co.jp": "Amazon",
        "amazon.com": "Amazon",
    ]

    /// ラベルの前に付ける絵文字（無ければ🔗）
    private static let emojiByLabel: [String: String] = [
        "Twitter": "🐦",
        "Instagram": "📷",
        "YouTube": "▶️",
        "Facebook": "👍",
        "TikTok": "🎵",
        "GitHub": "🐙",
        "note": "📝",
        "Qiita": "🟢",
        "Zenn": "💧",
        "Wikipedia": "📖",
        "Amazon": "📦",
    ]

    /// 「co.jp」のような2段階TLD
    private static let twoPartTlds: Set<String> = [
        "co.jp", "ne.jp", "or.jp", "go.jp", "ac.jp",
        "co.uk", "com.au", "co.kr", "com.br",
    ]

    /// ホスト名からサービスの表示名を求める
    static func domainLabel(host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        if let brand = brandByDomain[h] { return brand }
        // 辞書の列挙順は不定なので、一致した中で最も長いドメインを採る（決定的にするため）
        let suffixMatch = brandByDomain
            .filter { h.hasSuffix("." + $0.key) }
            .max { $0.key.count < $1.key.count }
        if let brand = suffixMatch?.value { return brand }
        return registrableName(h)
    }

    /// ラベルに対応する絵文字
    static func labelEmoji(_ label: String) -> String { emojiByLabel[label] ?? "🔗" }

    /// 未知ドメインは登録可能名の主要ラベルを見出しにする（例: asahi.co.jp → Asahi）
    private static func registrableName(_ host: String) -> String {
        let parts = host.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard parts.count > 1 else { return host.capitalizedFirst }
        let tldLen = (parts.count >= 3 && twoPartTlds.contains(parts.suffix(2).joined(separator: "."))) ? 2 : 1
        let index = parts.count - tldLen - 1
        let name = (index >= 0 && index < parts.count) ? parts[index] : parts[0]
        return name.capitalizedFirst
    }

    /// アイテムをドメイン別にまとめる。
    /// グループ内は保存日時の新しい順、グループ自体は「最新保存があるグループ」順。
    static func group(_ items: [StashItem]) -> [DomainGroup] {
        Dictionary(grouping: items) { domainLabel(host: $0.host) }
            .map { DomainGroup(label: $0.key, items: $0.value.sorted { $0.savedAt > $1.savedAt }) }
            .sorted { lhs, rhs in
                let l = lhs.items.map(\.savedAt).max() ?? 0
                let r = rhs.items.map(\.savedAt).max() ?? 0
                // 同着でも並びが揺れないようラベルで決着させる
                return l == r ? lhs.label < rhs.label : l > r
            }
    }
}

private extension String {
    /// 先頭1文字だけ大文字にする（Kotlinの replaceFirstChar { it.uppercase() } 相当）
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
