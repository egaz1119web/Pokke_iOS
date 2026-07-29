import Foundation

/// 端末内AI（Foundation Models）に渡す「保存済みリンクの要約」と質問文の組み立て。
///
/// 端末内モデルは文脈がとても短い（4096トークン前後）ので、保存件数が増えても全件は渡せない。
/// ここでは質問文と語が重なるリンクを先に選び、余った枠を新しい順で埋めてから、
/// 1件あたり数行に切り詰めた一覧を作る。
///
/// Foundation Modelsに依存しない純粋なロジックなので、通常のユニットテストで挙動を固定できる。
/// Android版 `data/AiDigest.kt` と同じ設計・同じ定数値。
enum AiDigest {

    /// 1回の質問でAIに見せるリンクの上限
    static let maxItems = 12

    /// 文脈全体の文字数の上限。端末内モデルの入力長に収めるための安全弁
    private static let maxContextChars = 2400

    private static let maxTitleChars = 90
    private static let maxNoteChars = 110

    /// タグ提案は1件だけを見るので、Q&Aより長く渡してよい
    private static let maxTagTitleChars = 120
    private static let maxTagNoteChars = 300

    /// 一度に出す候補の数。多いと的が絞れず、少ないと選ぶ楽しさが無い
    static let maxTagSuggestions = 4

    /// タグとして長すぎるものは、モデルが説明文を混ぜて返したとみなして捨てる
    private static let maxTagChars = 24

    /// プロンプトに載せる、既に使っているタグ語彙の上限。多いと文脈を圧迫する
    private static let maxVocabularyTags = 20

    /// 全体の要約で挙げるサイト・タグの数
    private static let topN = 3

    /// これ以上の割合に当たる語は、絞り込みに使えないとみなす
    private static let commonTermRatio = 0.4

    /// 語のありふれ具合を見はじめる件数。これ未満なら全部の語を使う
    private static let minItemsForCommonTerms = 10

    /// 語として短すぎて、どのリンクにも当たってしまうもの
    private static let stopWords: Set<String> = [
        "the", "and", "for", "you", "was", "are", "what", "which", "when", "who",
        "how", "about", "with", "from", "この", "その", "あの", "どの", "ある", "する",
        "して", "した", "教えて", "ですか", "ください",
    ]

    /// 質問に関係のありそうなリンクを `limit` 件まで選ぶ。
    ///
    /// 一致したものがあれば、それだけを返す。枠が余っても新着で埋めない
    /// ——小さいモデルに無関係な記事を混ぜると、そちらに引っ張られて答えが濁る。
    /// 一致が1件も無いとき（「最近なに保存した？」のような、内容の語を
    /// 含まない質問）だけ、答える材料として新しい順に渡す。
    static func selectRelevant(items: [StashItem], question: String, limit: Int = maxItems) -> [StashItem] {
        guard !items.isEmpty, limit > 0 else { return [] }
        let terms = discriminating(items: items, terms: terms(from: question))
        let hits: [StashItem]
        if terms.isEmpty {
            hits = []
        } else {
            hits = items
                .map { ($0, score(item: $0, terms: terms)) }
                .filter { $0.1 > 0 }
                // 同点なら新しいものを優先する
                .sorted {
                    if $0.1 != $1.1 { return $0.1 > $1.1 }
                    return $0.0.savedAt > $1.0.savedAt
                }
                .prefix(limit)
                .map(\.0)
        }
        // 一致したものは関係が濃い順のまま渡す。1件ずつに保存日を書いてあるので
        // 日付は読み取れるし、いちばん関係のあるものが末尾に埋もれる方が損が大きい。
        // 一致が無いときだけ、新しい順に渡す
        return hits.isEmpty ? Array(items.sorted { $0.savedAt > $1.savedAt }.prefix(limit)) : hits
    }

    /// 絞り込みの役に立つ語だけを残す。
    ///
    /// 「ラーメンの記事あった？」の「記事」のように、保存したリンクの多くに
    /// 含まれてしまう語で点が入ると、本命が新着の山に埋もれる。
    /// 全体の `commonTermRatio` を超えて当たる語は、区別に使えないので捨てる。
    /// 母数が小さいうちは「多く当たる」ことに意味があるので何もしない。
    private static func discriminating(items: [StashItem], terms: Set<String>) -> Set<String> {
        guard items.count >= minItemsForCommonTerms, !terms.isEmpty else { return terms }
        let limit = Double(items.count) * commonTermRatio
        let kept = terms.filter { term in
            Double(items.filter { score(item: $0, terms: [term]) > 0 }.count) <= limit
        }
        // 全部がありふれた語だったら絞らない。ここで空にすると、
        // 一致ゼロ扱いになって新着だけの回答に落ちてしまう
        return kept.isEmpty ? terms : kept
    }

    /// AIに読ませる文脈を組み立てる。
    ///
    /// 冒頭に `all`（対象範囲の全リンク）から集計した要約を置き、そのあとに
    /// `selected` だけを詳しく並べる。要約は件数・期間・よく保存しているサイトと
    /// タグなので、詳しく見せられるのが一部でも「全体で何があるか」は正しく答えられる。
    /// 一部しか見ていないことも明記して、全部を見たかのように答えさせない。
    static func buildContext(all: [StashItem], selected: [StashItem], now: EpochMillis) -> String {
        var text = overview(all: all, selected: selected, now: now)
        for (index, item) in selected.enumerated() {
            var block = "\n[\(index + 1)] \(truncate(item.title, maxTitleChars))\n"
            block += "  site: \(item.siteName ?? item.host)\n"
            block += "  saved: \(formatDate(item.savedAt))\n"
            if !item.tags.isEmpty {
                block += "  tags: \(item.tags.joined(separator: ", "))\n"
            }
            if let note = item.description.map(collapseWhitespace), !note.isEmpty {
                block += "  note: \(truncate(note, maxNoteChars))\n"
            }
            // 途中で打ち切るので、入り切らない1件はまるごと落とす。
            // 半端に切れた行が残ると、AIが別のリンクの情報と混ぜてしまう
            if text.count + block.count > maxContextChars { return text }
            text += block
        }
        return text
    }

    /// 実際にAIへ送る一本の文字列。
    ///
    /// `instruction` は表示中の言語のもの（Localizable.xcstrings）を渡す。
    /// これで回答も利用者の言語になる。
    static func buildPrompt(instruction: String, context: String, question: String) -> String {
        var text = instruction + "\n\n"
        text += "--- SAVED LINKS ---\n"
        text += context.trimmingTrailingWhitespace() + "\n"
        text += "--- QUESTION ---\n"
        text += question.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        text += "--- ANSWER ---\n"
        return text
    }

    /// 保存済み全体でよく使われているタグを、多い順に `maxVocabularyTags` 件まで。
    ///
    /// タグ提案のプロンプトに載せて「新しい言い回しより使い慣れたタグの再利用」を
    /// 促すのに使う。ここで頻度順にしておくと、よく使うタグほど優先して渡せる。
    static func tagVocabulary(_ items: [StashItem]) -> [String] {
        var counts: [String: Int] = [:]
        for tag in items.flatMap(\.tags) { counts[tag, default: 0] += 1 }
        return counts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.lowercased() < $1.key.lowercased()
        }
        .prefix(maxVocabularyTags)
        .map(\.key)
    }

    /// タグ提案用に、1件ぶんだけの文脈と指示をまとめた文字列。
    ///
    /// Q&Aと違って他のリンクとの混同を心配しなくていいので、複数件から
    /// 絞り込む `selectRelevant` は使わず、この1件のタイトル・サイト・本文だけを渡す。
    static func buildTagPrompt(instruction: String, item: StashItem, vocabulary: [String] = []) -> String {
        var text = instruction + "\n\n"
        text += "--- LINK ---\n"
        text += "title: \(truncate(item.title, maxTagTitleChars))\n"
        text += "site: \(item.siteName ?? item.host)\n"
        if let note = item.description.map(collapseWhitespace), !note.isEmpty {
            text += "note: \(truncate(note, maxTagNoteChars))\n"
        }
        // 既に付いているタグと同じものを提案されても選べないので、避けるよう伝える
        if !item.tags.isEmpty {
            text += "tags already on this link: \(item.tags.joined(separator: ", "))\n"
        }
        // 他のリンクで使っているタグを見せて、新しい言い回しより再利用を促す。
        // これをしないと、似た意味のタグが少しずつ違う書き方で増えていく
        let reusable = vocabulary.filter { !item.tags.contains($0) }
        if !reusable.isEmpty {
            text += "existing tags, reuse one if it fits: \(reusable.joined(separator: ", "))\n"
        }
        text += "--- TAGS ---\n"
        return text
    }

    /// 構造化出力（`TagSuggestions.tags`）で受け取った候補を仕上げる。
    ///
    /// モデルは指示通りに動かず、既存タグと同じものやわずかな表記ゆれ
    /// （大小文字・スペース・記号違い）を返すことがあるので、ここで機械的に均す。
    /// 大小文字やスペース・記号だけが違う表記ゆれは `vocabulary` の綴りに揃え、
    /// 揃えられたものを新規の候補より先に出す。
    static func refineTagSuggestions(_ raw: [String], existing: [String], vocabulary: [String] = []) -> [String] {
        let existingLower = Set(existing.map { $0.lowercased() })
        let candidates = raw
            // 指示ではハッシュタグ記号を付けないよう伝えているが、念のため取り除く
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingLeadingHash() }
            .filter { !$0.isEmpty && $0.count <= maxTagChars && !existingLower.contains($0.lowercased()) }

        var seen = Set<String>()
        let deduped = candidates.filter { seen.insert($0.lowercased()).inserted }

        let snapped = deduped.map { candidate in
            vocabulary.first { normalizeTag($0) == normalizeTag(candidate) } ?? candidate
        }
        var seenSnapped = Set<String>()
        let dedupedSnapped = snapped
            .filter { seenSnapped.insert($0.lowercased()).inserted }
            .filter { !existingLower.contains($0.lowercased()) }

        let reused = dedupedSnapped.filter { candidate in vocabulary.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame } }
        let fresh = dedupedSnapped.filter { candidate in !vocabulary.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame } }
        return Array((reused + fresh).prefix(maxTagSuggestions))
    }

    /// 表記ゆれ比較用に、大小文字とスペース・記号を落とした形にする
    private static func normalizeTag(_ tag: String) -> String {
        tag.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 対象範囲の全リンクから集計した、数行の要約
    private static func overview(all: [StashItem], selected: [StashItem], now: EpochMillis) -> String {
        // 「先週保存した記事」のような相対的な質問に答えるには基準日が要る
        var text = "TODAY: \(formatDate(now))\n"
        guard !all.isEmpty else { return text }
        let minSaved = all.map(\.savedAt).min() ?? now
        let maxSaved = all.map(\.savedAt).max() ?? now
        text += "TOTAL: \(all.count) links saved between \(formatDate(minSaved)) and \(formatDate(maxSaved))\n"
        let unread = all.filter(\.unread).count
        if unread > 0 { text += "UNREAD: \(unread)\n" }
        if let sites = topCounts(all.map { $0.siteName ?? $0.host }) {
            text += "TOP SITES: \(sites)\n"
        }
        if let tags = topCounts(all.flatMap(\.tags)) {
            text += "TOP TAGS: \(tags)\n"
        }
        // ここを書かないと、一部しか渡していないのに全部を見たつもりで
        // 「保存しているのはこれだけです」と言い切ってしまう
        text += "DETAILS BELOW: "
        if selected.count >= all.count {
            text += "all \(all.count) of them"
        } else {
            text += "\(selected.count) of them, picked for this question"
        }
        text += "\n"
        return text
    }

    /// 「youtube.com (41), x.com (33)」のような、多い順の上位いくつか
    private static func topCounts(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts
            // 同数のときは名前順。並びが実行のたびに変わると挙動を追えない
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(topN)
            .map { "\($0.key) (\($0.value))" }
            .joined(separator: ", ")
    }

    private static func score(item: StashItem, terms: Set<String>) -> Int {
        let title = item.title.lowercased()
        let tags = item.tags.joined(separator: " ").lowercased()
        let site = ((item.siteName ?? "") + " " + item.host).lowercased()
        let note = (item.description ?? "").lowercased()
        return terms.reduce(0) { sum, term in
            if title.contains(term) { return sum + 3 }
            if tags.contains(term) { return sum + 3 }
            if site.contains(term) { return sum + 2 }
            if note.contains(term) { return sum + 1 }
            return sum
        }
    }

    /// 質問を照合用の語に割る。
    ///
    /// 日本語・韓国語・中国語は語の間に空白が無いので、空白で切るだけだと
    /// 質問全体が1語になって何にも当たらない。CJKを含む塊は2文字ずつの
    /// 部分文字列にも展開して、部分一致で拾えるようにしている。
    private static func terms(from question: String) -> Set<String> {
        let chunks = question.lowercased().components(separatedBy: nonWordCharacters)
        var result = Set<String>()
        for chunk in chunks {
            guard chunk.count >= 2, !stopWords.contains(chunk) else { continue }
            if chunk.contains(where: isCjk) {
                let characters = Array(chunk)
                for i in 0...(characters.count - 2) {
                    let bigram = String(characters[i...(i + 1)])
                    if !stopWords.contains(bigram) { result.insert(bigram) }
                }
            } else {
                result.insert(chunk)
            }
        }
        return result
    }

    private static let nonWordCharacters = CharacterSet.alphanumerics.inverted

    private static func isCjk(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x3040...0x30FF).contains(value) || // かな
            (0x3400...0x9FFF).contains(value) || // 漢字
            (0xAC00...0xD7AF).contains(value) // ハングル
    }

    /// Android版と同じく端末のタイムゾーンで日付を出す（「先週」のような相対質問は
    /// 端末のカレンダー感覚に合わせた方が自然なため）
    private static func formatDate(_ millis: EpochMillis) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date(epochMillis: millis))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func truncate(_ text: String, _ max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max)).trimmingTrailingWhitespace() + "…"
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last.isWhitespace || last.isNewline {
            result.removeLast()
        }
        return result
    }

    func trimmingLeadingHash() -> String {
        hasPrefix("#") ? String(dropFirst()).trimmingCharacters(in: .whitespaces) : self
    }
}
