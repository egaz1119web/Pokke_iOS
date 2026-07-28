import Foundation

/// ドメイン別まとめの1グループ
struct DomainGroup: Identifiable, Equatable {
    var label: String
    /// ロゴ取得に使う代表ドメイン（例: Twitter → x.com）
    var domain: String
    var items: [StashItem]
    /// 1件しかないサービスをまとめた「その他」グループか。表示名はUI側で解決する
    var isOther: Bool = false

    var id: String { label }
}

/// 保存アイテムをドメイン（サービス）ごとにまとめるロジック。純関数で単体テスト対象。
/// 例: twitter.com / x.com → "Twitter"、youtu.be / youtube.com → "YouTube"
enum DomainGrouping {

    /// 主要サービスの表示名。サブドメインにも一致させる。
    /// 順序を持たせているのは、同じラベルを指す複数ドメインの「代表」を
    /// 先に書いた方に決めるため（Kotlinの LinkedHashMap と同じ扱い）。
    private static let brandByDomain: [(domain: String, label: String)] = [
        ("twitter.com", "Twitter"),
        ("x.com", "Twitter"),
        ("instagram.com", "Instagram"),
        ("youtube.com", "YouTube"),
        ("youtu.be", "YouTube"),
        ("facebook.com", "Facebook"),
        ("tiktok.com", "TikTok"),
        ("github.com", "GitHub"),
        ("note.com", "note"),
        ("qiita.com", "Qiita"),
        ("zenn.dev", "Zenn"),
        ("wikipedia.org", "Wikipedia"),
        ("amazon.co.jp", "Amazon"),
        ("amazon.com", "Amazon"),
    ]

    /// 「co.jp」のような2段階TLD
    private static let twoPartTlds: Set<String> = [
        "co.jp", "ne.jp", "or.jp", "go.jp", "ac.jp",
        "co.uk", "com.au", "co.kr", "com.br",
    ]

    /// ホスト名からサービスの表示名を求める
    static func domainLabel(host: String) -> String {
        let h = normalizedHost(host)
        if let brand = brandByDomain.first(where: { $0.domain == h }) { return brand.label }
        if let brand = brandByDomain.first(where: { h.hasSuffix("." + $0.domain) }) { return brand.label }
        return registrableName(h)
    }

    /// ロゴ画像を引くための代表ドメイン。
    /// twitter.com と x.com のように別ホストが同じサービスの場合、
    /// ロゴが1種類に揃うよう正規化する。
    static func logoDomain(host: String) -> String {
        let h = normalizedHost(host)
        if let canonical = canonicalDomain(h) { return canonical }
        return registrableDomain(host: h)
    }

    /// ブランド表に載っているホストなら、その代表ドメインを返す
    private static func canonicalDomain(_ host: String) -> String? {
        let matched = brandByDomain.first { $0.domain == host }
            ?? brandByDomain.first { host.hasSuffix("." + $0.domain) }
        guard let label = matched?.label else { return nil }
        // 同じラベルを指すドメインのうち先に定義したものを代表とする
        return brandByDomain.first { $0.label == label }?.domain
    }

    /// ホスト名から登録可能ドメインを取り出す（例: m.asahi.co.jp → asahi.co.jp）
    static func registrableDomain(host: String) -> String {
        let h = normalizedHost(host)
        let parts = h.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        if parts.count <= 2 { return h }
        let tldLen = twoPartTlds.contains(parts.suffix(2).joined(separator: ".")) ? 2 : 1
        return parts.suffix(tldLen + 1).joined(separator: ".")
    }

    /// 未知ドメインは登録可能名の主要ラベルを見出しにする（例: asahi.co.jp → Asahi）
    private static func registrableName(_ host: String) -> String {
        let parts = host.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        guard parts.count > 1 else { return host.capitalizedFirst }
        let tldLen = (parts.count >= 3 && twoPartTlds.contains(parts.suffix(2).joined(separator: "."))) ? 2 : 1
        let index = parts.count - tldLen - 1
        let name = (index >= 0 && index < parts.count) ? parts[index] : parts[0]
        return name.capitalizedFirst
    }

    private static func normalizedHost(_ host: String) -> String {
        let h = host.lowercased()
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// 「その他」グループの識別子。表示名はUI側で文字列リソースから解決する
    static let otherLabel = "__other__"

    /// アイテムをドメイン別にまとめる。
    ///
    /// - グループ内は保存日時の新しい順
    /// - グループは件数の多い順（同数なら最新保存が新しい方が先）
    /// - 1件しかないサービスは「その他」へまとめる。タブが1件のサービスで
    ///   埋まって目的のサービスが探せなくなるのを防ぐため。
    ///   ただし1件のサービスが1つしか無いときは、まとめても意味がないのでそのまま残す
    static func group(_ items: [StashItem]) -> [DomainGroup] {
        let byLabel = Dictionary(grouping: items) { domainLabel(host: $0.host) }
        let singleItemLabels = Set(byLabel.filter { $0.value.count == 1 }.keys)
        let collapse = singleItemLabels.count >= 2

        let source = collapse ? byLabel.filter { !singleItemLabels.contains($0.key) } : byLabel
        let named = source
            .map { label, list -> DomainGroup in
                let sorted = list.sorted { $0.savedAt > $1.savedAt }
                return DomainGroup(
                    label: label,
                    domain: logoDomain(host: sorted[0].host),
                    items: sorted
                )
            }
            .sorted { lhs, rhs in
                if lhs.items.count != rhs.items.count { return lhs.items.count > rhs.items.count }
                let l = lhs.items.map(\.savedAt).max() ?? 0
                let r = rhs.items.map(\.savedAt).max() ?? 0
                // 同着でも並びが揺れないようラベルで決着させる（辞書の列挙順は不定なため）
                return l == r ? lhs.label < rhs.label : l > r
            }
        if !collapse { return named }

        let others = singleItemLabels
            .flatMap { byLabel[$0] ?? [] }
            .sorted { $0.savedAt > $1.savedAt }
        // 「その他」は件数に関係なく末尾
        return named + [DomainGroup(label: otherLabel, domain: "", items: others, isOther: true)]
    }
}

extension String {
    /// 先頭1文字だけ大文字にする（Kotlinの replaceFirstChar { it.uppercase() } 相当）
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
