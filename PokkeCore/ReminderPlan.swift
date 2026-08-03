import Foundation

/// リマインダーの「いつ鳴らすか」を決めるところ。
///
/// 通知そのもの（UserNotifications）はアプリ側の `ReminderScheduler` が担当し、
/// ここは時刻の計算だけを持つ純粋なロジック。カレンダーを引数で受け取るので、
/// タイムゾーン固定のユニットテストで挙動を固定できる。
/// iOS固有の機能で、Android版には対応するファイルが無い。
enum ReminderPlan {

    /// ワンタップで選べる候補。すべて「今から必ず未来」になるものだけを並べる
    enum Preset: String, CaseIterable, Identifiable {
        /// 3時間後。今日のうちにもう一度見たいもの向け
        case inThreeHours
        /// 明日の朝
        case tomorrowMorning
        /// 次の土曜の午前
        case weekend
        /// 1週間後の朝
        case nextWeek

        var id: String { rawValue }

        /// Localizable.xcstrings のキー
        var labelKey: String { "reminder_preset_\(rawValue)" }
    }

    /// 朝いちで思い出したい時刻
    static let morningHour = 9
    /// 週末はもう少しゆっくりでよい
    static let weekendHour = 10
    /// これより手前には置かない。押した直後に鳴るリマインダーは意味が無い
    static let minimumLeadMinutes = 5
    /// AIに任せたときに許す先送りの上限（日）
    static let maxDelayDays = 90
    /// 22時〜翌8時は寝ている時間とみなし、この帯には置かない
    static let nightStartHour = 22
    static let nightEndHour = 8

    /// 候補ひとつぶんの時刻
    static func date(for preset: Preset, now: Date, calendar: Calendar = .current) -> Date {
        switch preset {
        case .inThreeHours:
            return truncateSeconds(now.addingTimeInterval(3 * 60 * 60), calendar: calendar)
        case .tomorrowMorning:
            return at(hour: morningHour, dayOffset: 1, from: now, calendar: calendar)
        case .weekend:
            // 「次の土曜」。今日が土曜でまだ時間前なら今日になる
            let saturday = DateComponents(hour: weekendHour, minute: 0, second: 0, weekday: 7)
            return calendar.nextDate(after: now, matching: saturday, matchingPolicy: .nextTime)
                ?? at(hour: weekendHour, dayOffset: 7, from: now, calendar: calendar)
        case .nextWeek:
            return at(hour: morningHour, dayOffset: 7, from: now, calendar: calendar)
        }
    }

    /// AIが答えた「何時間後」を実際の時刻に落とす。
    ///
    /// モデルは 0 や 10000 のような使えない値も返してくるので、まず幅に収めてから、
    /// 深夜に当たったぶんを朝へ寄せる。利用者に見せる前に必ずここを通す。
    static func resolve(hoursFromNow: Int, now: Date, calendar: Calendar = .current) -> Date {
        let hours = min(max(hoursFromNow, 1), maxDelayDays * 24)
        let target = now.addingTimeInterval(TimeInterval(hours) * 60 * 60)
        return avoidingNight(target, now: now, calendar: calendar)
    }

    /// 寝ている時間帯を避ける。
    /// 明け方なら同じ日の朝へ、深夜なら翌朝へ送る（送った結果が現在より手前に
    /// なることは無い ── 元が未来なら、朝へ寄せても未来のままになる幅しか動かさない）
    static func avoidingNight(_ date: Date, now: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        var adjusted = date
        if hour < nightEndHour {
            adjusted = at(hour: morningHour, dayOffset: 0, from: date, calendar: calendar)
        } else if hour >= nightStartHour {
            adjusted = at(hour: morningHour, dayOffset: 1, from: date, calendar: calendar)
        }
        return notBefore(adjusted, now: now, calendar: calendar)
    }

    /// 今より手前（や、今すぐ鳴ってしまう位置）に来ないよう押し戻す
    static func notBefore(_ date: Date, now: Date, calendar: Calendar = .current) -> Date {
        let earliest = now.addingTimeInterval(TimeInterval(minimumLeadMinutes) * 60)
        return truncateSeconds(max(date, earliest), calendar: calendar)
    }

    /// まだ鳴っていないリマインダーが付いているか
    static func isPending(_ remindAt: EpochMillis?, now: EpochMillis) -> Bool {
        guard let remindAt else { return false }
        return remindAt > now
    }

    /// 端末内AIに渡す一本の文字列。
    ///
    /// `instruction` は表示中の言語のもの（Localizable.xcstrings）を渡す。
    /// 曜日と時刻まで書いておかないと「週末に」「明日の朝」のような判断ができない。
    static func buildPrompt(
        instruction: String,
        item: StashItem,
        now: EpochMillis,
        calendar: Calendar = .current
    ) -> String {
        var text = instruction + "\n\n"
        text += "--- NOW ---\n"
        text += "\(formatNow(now, calendar: calendar))\n"
        text += "--- LINK ---\n"
        text += "title: \(truncate(item.title, 120))\n"
        text += "site: \(item.siteName ?? item.host)\n"
        text += "saved: \(formatDay(item.savedAt, calendar: calendar))\n"
        if !item.tags.isEmpty {
            text += "tags: \(item.tags.joined(separator: ", "))\n"
        }
        if let note = item.description.map(collapseWhitespace), !note.isEmpty {
            text += "note: \(truncate(note, 300))\n"
        }
        text += "--- WHEN ---\n"
        return text
    }

    /// AIが添えてきた理由を表示できる形に整える。空なら見せない
    static func refineReason(_ raw: String) -> String? {
        let text = collapseWhitespace(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count <= 60 ? text : String(text.prefix(60)) + "…"
    }

    // MARK: - 内部

    /// `dayOffset` 日ずらした日の `hour` 時ちょうど
    private static func at(hour: Int, dayOffset: Int, from date: Date, calendar: Calendar) -> Date {
        let base = calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? base
    }

    /// 通知は分単位でしか指定しないので、秒は落としておく
    private static func truncateSeconds(_ date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    private static func formatNow(_ millis: EpochMillis, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm (EEEE)"
        return formatter.string(from: Date(epochMillis: millis))
    }

    private static func formatDay(_ millis: EpochMillis, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(epochMillis: millis))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func truncate(_ text: String, _ max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "…"
    }
}
