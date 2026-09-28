import Foundation

/// リンクの内容から見つけた、カレンダーに入れられそうな予定1件
struct CalendarCandidate: Equatable, Identifiable {
    let year: Int
    /// 1〜12
    let month: Int
    let day: Int
    /// 時刻が書かれていなければ nil。そのときは終日の予定にする
    var hour: Int?
    var minute: Int?
    let label: String

    var id: String { "\(year)-\(month)-\(day)-\(hour ?? -1)-\(minute ?? -1)" }
    var allDay: Bool { hour == nil }

    /// 予定の始まり。終日なら [timeZone] でのその日の0時
    func beginDate(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour ?? 0, minute: minute ?? 0
        )) ?? Date()
    }

    /// 終日なら翌日の0時、時刻があれば1時間後
    func endDate(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let begin = beginDate(timeZone: timeZone)
        return calendar.date(byAdding: allDay ? .day : .hour, value: 1, to: begin) ?? begin
    }
}

/// 本文に実際に書かれていた日付1つ。年・時刻は書かれていなければ nil
struct DateMention: Equatable {
    let year: Int?
    let month: Int
    let day: Int
    var hour: Int?
    var minute: Int?
}

/// 保存したリンクのタイトル・本文から、発売日や入荷日のような予定を端末内AIで拾う。
///
/// どの日付が予定なのか・何の予定なのかを決めるのはモデルに任せるが、小さいモデルは
/// 書かれていない日付を作ったり、「10/23 発売」に 0:00 のような時刻を付けたりする。
/// そこで本文に書かれている日付は `findDates` でこちらでも拾っておき、
///
/// - モデルの日付は、本文に同じ月日が日付として書かれているものだけを採る
/// - 時刻はモデルの答えを使わず、本文でその日付に添えて書かれているときだけ付ける
/// - 年は本文に書かれていればそれを、無ければ保存した日から決める
///
/// という形で、モデルの答えを本文の裏付けがある範囲に絞る。Android版の
/// `CalendarExtract.kt` と同じ判定にしてある（正規表現もどちらもICU）。
enum CalendarExtract {

    static let maxCandidates = 3

    private static let maxTitleChars = 160
    private static let maxNoteChars = 900
    private static let maxLabelChars = 40
    private static let minLabelChars = 4
    private static let minSubjectChars = 8
    private static let maxDateWordsChars = 16
    private static let maxSummaryTitleChars = 160
    private static let maxSummaryNoteChars = 1500
    private static let maxSummaryChars = 400
    private static let fallbackNoteChars = 300

    /// 年が書かれていないとき、保存日のこれだけ前までは「過去の話」として許す
    private static let pastWindowDays = 60

    private static let monthNames = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ]

    // MARK: - 本文の日付

    /// 日付らしい書き方が1つも無ければ、AIに聞く入口も出さない
    static func mayContainDate(_ item: StashItem) -> Bool {
        !findDates(normalize(sourceText(item))).isEmpty
    }

    /// 本文に書かれている日付を拾う。
    ///
    /// 「8月24日」「2026年8月24日」「10/23」「2026/10/23」「2026-10-23」「Oct 23」「23 Oct」
    /// 「10월 23일」の形に対応し、直後（曜日の括弧を挟んでもよい）に「10:00」「18時」
    /// 「18時30分」があればその時刻も持たせる。`text` は `normalize` 済みであること。
    static func findDates(_ text: String) -> [DateMention] {
        var found: [DateMention] = []
        func add(_ year: String?, _ month: Int, _ day: Int, _ m: Match, timeGroup: Int) {
            guard (1...12).contains(month), (1...31).contains(day) else { return }
            var hour: Int?
            var minute: Int?
            if let h = m[timeGroup].flatMap(Int.init), let mi = m[timeGroup + 1].flatMap(Int.init) {
                hour = h; minute = mi
            } else if let h = m[timeGroup + 2].flatMap(Int.init) {
                hour = h; minute = m[timeGroup + 3].flatMap(Int.init) ?? 0
            }
            let validTime = hour.map { (0...23).contains($0) } == true
                && minute.map { (0...59).contains($0) } == true
            found.append(DateMention(
                year: year.flatMap(Int.init),
                month: month,
                day: day,
                hour: validTime ? hour : nil,
                minute: validTime ? minute : nil
            ))
        }
        for m in matches(cjkDate, in: text) {
            add(m[1], Int(m[2] ?? "") ?? 0, Int(m[3] ?? "") ?? 0, m, timeGroup: 4)
        }
        for m in matches(ymdDate, in: text) {
            add(m[1], Int(m[2] ?? "") ?? 0, Int(m[3] ?? "") ?? 0, m, timeGroup: 4)
        }
        for m in matches(mdDate, in: text) where !isFraction(text, m) {
            add(nil, Int(m[1] ?? "") ?? 0, Int(m[2] ?? "") ?? 0, m, timeGroup: 3)
        }
        let lower = text.lowercased()
        for m in matches(enMonthDay, in: lower) {
            add(m[3], monthOf(m[1] ?? ""), Int(m[2] ?? "") ?? 0, m, timeGroup: 4)
        }
        for m in matches(enDayMonth, in: lower) {
            add(m[3], monthOf(m[2] ?? ""), Int(m[1] ?? "") ?? 0, m, timeGroup: 4)
        }
        return found
    }

    // MARK: - プロンプトと返答

    static func buildPrompt(instruction: String, item: StashItem, now: Date) -> String {
        var text = instruction + "\n\n"
        // 年の無い日付を読むときの手がかり。無いと学習時点の年を付けてしまう
        text += "TODAY: \(formatDate(now))\n"
        text += "SAVED: \(formatDate(Date(epochMillis: item.savedAt)))\n"
        text += "--- LINK ---\n"
        text += "title: \(truncate(collapseWhitespace(item.title), maxTitleChars))\n"
        if let note = item.description.map(collapseWhitespace), !note.isEmpty {
            text += "note: \(truncate(note, maxNoteChars))\n"
        }
        text += "--- EVENTS ---\n"
        return text
    }

    /// モデルの返答から予定を取り出す。
    ///
    /// 「YYYY-MM-DD [HH:MM] | 予定名」の1行1件で、と指示しているが、区切りが
    /// コロンや全角の縦棒だったり、先頭に番号や記号が付いたりするので緩めに読む。
    static func parse(_ raw: String, item: StashItem, timeZone: TimeZone = .current) -> [CalendarCandidate] {
        let source = normalize(sourceText(item))
        let mentions = findDates(source)
        let noise = labelNoise(item)
        var seen = Set<String>()
        var result: [CalendarCandidate] = []
        for line in raw.components(separatedBy: .newlines) {
            guard let m = matches(lineRegex, in: normalize(line)).first,
                  let month = m[2].flatMap(Int.init), let day = m[3].flatMap(Int.init),
                  let modelYear = m[1].flatMap(Int.init) else { continue }
            let rest = m[6] ?? ""
            // 本文に日付として書かれていない月日は、モデルの作り話とみなす
            let sameDay = mentions.filter { $0.month == month && $0.day == day }
            if sameDay.isEmpty { continue }
            let year = sameDay.compactMap(\.year).first
                ?? (mentionsNumber(source, modelYear) ? modelYear : nil)
                ?? inferYear(month: month, day: day, savedAt: item.savedAt, timeZone: timeZone)
            guard isValidDate(year: year, month: month, day: day) else { continue }
            // 時刻は本文でその日付に添えられているときだけ。モデルが付けた時刻は
            // 「発売」だけの日にも 0:00 を入れてくるので使わない。
            // 同じ日付に違う時刻が並んでいたら、どれか決められないので終日にする
            let times = sameDay.compactMap { mention in mention.hour.map { "\($0):\(mention.minute ?? 0)" } }
            let distinctTimes = Array(Set(times))
            let time = distinctTimes.count == 1 ? sameDay.first { $0.hour != nil } : nil

            let stripped = cleanLabel(stripNoise(rest, noise))
            // アカウント名を落とすと「発売」「予告」だけ残ったり、何も残らなかったりする。
            // そのときは予定名をこちらで組み立てる。初めから短い予定名
            // （「予約開始」など）をモデルが付けてきたときはそのままにする
            let usable = stripped.count > minLabelChars
                || (!stripped.isEmpty && stripped == cleanLabel(rest))
            let label = usable ? stripped : composeLabel(item, source: source, month: month, day: day, leftover: stripped)

            let candidate = CalendarCandidate(
                year: year, month: month, day: day,
                hour: time?.hour, minute: time?.minute,
                label: label
            )
            if seen.insert(candidate.id).inserted { result.append(candidate) }
        }
        return Array(
            result.sorted { ($0.year, $0.month, $0.day, $0.hour ?? -1) < ($1.year, $1.month, $1.day, $1.hour ?? -1) }
                .prefix(maxCandidates)
        )
    }

    /// 年の書かれていない月日に年を付ける。
    ///
    /// 告知は予定より前に出るので、基本は保存日以降で一番近い日にする。ただし
    /// 少し前の告知を後から保存することもあるので、保存日の `pastWindowDays` 日前までは
    /// 同じ年のまま扱う（2月に保存した「12月20日発売」を翌年12月にしない）。
    static func inferYear(month: Int, day: Int, savedAt: EpochMillis, timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let saved = Date(epochMillis: savedAt)
        let savedYear = calendar.component(.year, from: saved)
        let earliest = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -pastWindowDays, to: saved) ?? saved
        )
        let sameYear = calendar.date(from: DateComponents(year: savedYear, month: month, day: day)) ?? saved
        return sameYear < earliest ? savedYear + 1 : savedYear
    }

    // MARK: - メモ欄の要約

    /// 予定のメモ欄に入れる要約を頼む文。予定の日付探しとは別に聞く。
    /// 1回で両方を頼むと、小さいモデルは書式が崩れて日付の行まで読めなくなる。
    static func buildSummaryPrompt(instruction: String, item: StashItem) -> String {
        var text = instruction + "\n\n"
        text += "--- LINK ---\n"
        text += "title: \(truncate(collapseWhitespace(item.title), maxSummaryTitleChars))\n"
        text += "site: \(item.siteName ?? item.host)\n"
        if let note = item.description.map(collapseWhitespace), !note.isEmpty {
            text += "note: \(truncate(note, maxSummaryNoteChars))\n"
        }
        text += "--- SUMMARY ---\n"
        return text
    }

    /// 要約の返答から、見出しや前置きを落とした本文だけを取り出す
    static func parseSummary(_ raw: String) -> String? {
        let body = raw.components(separatedBy: .newlines)
            .map { line -> String in
                var t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("-") || t.hasPrefix("*") { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
                return replace(summaryLabel, in: t, with: "").trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("---") }
            .joined(separator: "\n")
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : truncate(body, maxSummaryChars)
    }

    /// カレンダーの予定のメモ欄に入れる文。
    ///
    /// 要約を先頭に、あとで元の告知へ戻れるようタイトルとリンクを続ける。
    /// 要約が取れなかったときは本文の頭をそのまま使う。
    static func calendarNotes(summary: String?, item: StashItem) -> String {
        var text = ""
        let body = summary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? item.description.map(collapseWhitespace).flatMap { $0.isEmpty ? nil : truncate($0, fallbackNoteChars) }
        if let body { text += body + "\n\n" }
        text += collapseWhitespace(item.title) + "\n"
        text += item.url
        return text
    }

    // MARK: - 予定名

    /// 予定名に混ざりがちな、投稿者のアカウント名やサイト名。
    ///
    /// SNSのリンクはタイトルが「アカウント名 / X」「アカウント名 - Instagram: "…」なので、
    /// 小さいモデルは予定名にそれをそのまま写してくる。予定名としては意味が無いので落とす
    private static func labelNoise(_ item: StashItem) -> [String] {
        [accountName(item), item.siteName, item.host].compactMap { $0 }.filter { $0.count >= 2 }
    }

    private static func accountName(_ item: StashItem) -> String? {
        matches(accountTitle, in: item.title).first?[1]?.trimmingCharacters(in: .whitespaces)
    }

    private static func stripNoise(_ label: String, _ noise: [String]) -> String {
        var result = label
        for word in noise { result = result.replacingOccurrences(of: word, with: "", options: .caseInsensitive) }
        return replace(snsSuffix, in: result, with: " ")
    }

    /// モデルの予定名が使えなかったときに「誰の・何の日か」を組み立てる。
    ///
    /// 誰の … SNSならアカウント名（「GU（ジーユー）」）、それ以外はタイトル。
    /// 何の日 … 本文でその日付と同じ行に書かれた語（「10/23(金) 販売開始予定」なら
    ///           「販売開始予定」）。無ければモデルが残した語を使う。
    ///
    /// 本文の1行目を使っていた頃は「⚡️予告⚡️」のような飾りの行を拾ってしまい、
    /// 「⚡予告⚡ 予告」という予定名になった
    private static func composeLabel(_ item: StashItem, source: String, month: Int, day: Int, leftover: String) -> String {
        let subject = accountName(item) ?? collapseWhitespace(item.title)
        guard let what = wordsNextToDate(source, month: month, day: day) ?? (leftover.isEmpty ? nil : leftover) else {
            return cleanLabel(subject)
        }
        // 何の日かが切れて消えないよう、長いときは誰の方を削る
        let room = max(maxLabelChars - what.count - 1, minSubjectChars)
        return cleanLabel(truncate(subject, room) + " " + what)
    }

    /// 本文でその月日が書かれた行から、日付の後ろに続く語（無ければ前の語）。
    /// 曜日・URL・記号は落とす。本文を先に見て、無ければタイトルを見る
    /// （SNSのタイトルは本文の頭を含むので、先に見ると「アカウント名 - Instagram」を拾う）
    private static func wordsNextToDate(_ source: String, month: Int, day: Int) -> String? {
        let lines = source.components(separatedBy: "\n")
        for line in Array(lines.dropFirst()) + Array(lines.prefix(1)) {
            let hit = [cjkDate, ymdDate, mdDate]
                .flatMap { matches($0, in: line) }
                .filter { m in findDates(m.value).contains { $0.month == month && $0.day == day } }
                .min { $0.range.location < $1.range.location }
            guard let hit else { continue }
            let ns = line as NSString
            let after = cleanWords(ns.substring(from: hit.range.location + hit.range.length))
            let before = cleanWords(ns.substring(to: hit.range.location))
            return [after, before].first { $0.filter(\.isLetter).count >= 2 }.map { truncate($0, maxDateWordsChars) }
        }
        return nil
    }

    private static func cleanWords(_ text: String) -> String {
        let removed = replace(weekday, in: replace(url, in: text, with: " "), with: " ")
        return collapseWhitespace(String(removed.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }))
    }

    private static func cleanLabel(_ raw: String) -> String {
        let trimSet = CharacterSet(charactersIn: "|｜-–—:：\"「」 *")
        return truncate(collapseWhitespace(raw).trimmingCharacters(in: trimSet), maxLabelChars)
    }

    // MARK: - 正規表現

    /// 曜日の括弧を挟んで続く「10:00」「18時」「18時30分」
    private static let timeAfter =
        #"(?:\s*[(（][^)）\n]{1,6}[)）])?\s*(?:(\d{1,2})\s*:\s*(\d{2})|(\d{1,2})\s*[時시](?:\s*(\d{1,2})\s*[分분])?)?"#

    private static let cjkDate = regex(#"(?:(\d{4})\s*[年년]\s*)?(\d{1,2})\s*[月월]\s*(\d{1,2})\s*[日일]"# + timeAfter)
    private static let ymdDate = regex(#"(?<![\d/.])(\d{4})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{1,2})(?![\d/])"# + timeAfter)
    /// 年の無い「10/23」。「2026/10/23」の後ろ半分や分数の一部は拾わない
    private static let mdDate = regex(#"(?<![\d/.])(\d{1,2})/(\d{1,2})(?![\d/])"# + timeAfter)

    private static let enMonth = #"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?"#
    private static let enMonthDay = regex(#"\b"# + enMonth + #"\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s*(\d{4}))?"# + timeAfter)
    private static let enDayMonth = regex(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+"# + enMonth + #"\b(?:,?\s*(\d{4}))?"# + timeAfter)

    private static let lineRegex = regex(
        #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})日?(?:\s*T?\s*(\d{1,2})\s*[:：時]\s*(\d{2})?分?)?\s*[|｜:：\-–—]?\s*(.*)"#
    )
    private static let accountTitle = regex(#"^(.+?)\s*(?:/\s*X\s*$|-\s*Instagram\b|on X\b|on Instagram\b)"#)
    private static let snsSuffix = regex(#"\s*/\s*X\b|\bon X\b|-\s*Instagram\b"#)
    private static let summaryLabel = regex(#"^(summary|要約|요약)\s*[:：]\s*"#, caseInsensitive: true)
    private static let url = regex(#"(?:https?://|pic\.twitter\.com/)\S+"#)
    private static let weekday = regex(#"[(（][^)）\n]{1,6}[)）]"#)

    /// 「小さじ1/2」「1/4に切る」のような分量・割合の「1/2」を日付と取り違えないよう、
    /// 直前の計量の語や直後の単位で見分ける。レシピのリンクで日付の入口が出ていた
    private static func isFraction(_ text: String, _ m: Match) -> Bool {
        let ns = text as NSString
        let start = m.range.location
        let end = m.groupRanges[2].location + m.groupRanges[2].length
        let before = ns.substring(with: NSRange(location: max(0, start - 3), length: start - max(0, start - 3)))
            .trimmingCharacters(in: .whitespaces)
        let after = ns.substring(with: NSRange(location: end, length: min(2, ns.length - end)))
        return fractionBefore.contains { before.hasSuffix($0) } || fractionAfter.contains { after.hasPrefix($0) }
    }

    private static let fractionBefore = ["さじ", "匙", "カップ", "杯", "約"]
    private static let fractionAfter = [
        "個", "本", "枚", "杯", "片", "株", "玉", "束", "量", "程", "cm", "g", "に切", "くらい", "ほど",
    ]

    private static func monthOf(_ name: String) -> Int {
        (monthNames.firstIndex(of: String(name.prefix(3))) ?? -1) + 1
    }

    // MARK: - 下請け

    /// 全角の数字・区切りを半角に揃える。SNSの告知文は「１０／２３」のように
    /// 全角で書かれていることが多い
    static func normalize(_ text: String) -> String {
        String(text.map { c -> Character in
            switch c {
            case "０"..."９":
                let offset = c.unicodeScalars.first!.value - ("０" as Unicode.Scalar).value
                return Character(Unicode.Scalar(("0" as Unicode.Scalar).value + offset)!)
            case "／": return "/"
            case "：": return ":"
            case "－": return "-"
            default: return c
            }
        })
    }

    private static func sourceText(_ item: StashItem) -> String {
        item.title + "\n" + (item.description ?? "")
    }

    /// 他の数字の一部ではない形で [n] が出てくるか。「08」のような0埋めも拾う
    private static func mentionsNumber(_ source: String, _ n: Int) -> Bool {
        !matches(regex(#"(?<!\d)0?\#(n)(?!\d)"#), in: source).isEmpty
    }

    private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        var components = DateComponents(year: year, month: month, day: day)
        components.calendar = Calendar(identifier: .gregorian)
        return components.isValidDate
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func truncate(_ text: String, _ max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// NSRegularExpression の1件の一致。グループは `m[i]` で文字列として取れる
    private struct Match {
        let value: String
        let range: NSRange
        let groupRanges: [NSRange]
        let groups: [String?]
        subscript(i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        // パターンはすべて固定の文字列なので、組み立てに失敗するなら書き間違い
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private static func matches(_ re: NSRegularExpression, in text: String) -> [Match] {
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { r in
            let ranges = (0..<r.numberOfRanges).map { r.range(at: $0) }
            return Match(
                value: ns.substring(with: r.range),
                range: r.range,
                groupRanges: ranges,
                groups: ranges.map { $0.location == NSNotFound ? nil : ns.substring(with: $0) }
            )
        }
    }

    private static func replace(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        re.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template
        )
    }
}
