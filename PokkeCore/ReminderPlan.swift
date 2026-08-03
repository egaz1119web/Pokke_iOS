import Foundation

/// リマインダーの「いつ鳴らすか」を決めるところ。
///
/// 通知そのもの（UserNotifications）はアプリ側の `ReminderScheduler` が担当し、
/// ここは時刻の計算だけを持つ純粋なロジック。カレンダーを引数で受け取るので、
/// タイムゾーン固定のユニットテストで挙動を固定できる。
/// iOS固有の機能で、Android版には対応するファイルが無い。
enum ReminderPlan {

    /// ワンタップで選べる候補。
    ///
    /// 細かい刻みを並べても結局「明日の朝」に落ち着くので、ひとつだけにしてある。
    /// それ以外の時刻は日時指定（`ReminderDateSheet`）で決める
    enum Preset: String, CaseIterable, Identifiable {
        /// 明日の朝
        case tomorrowMorning

        var id: String { rawValue }

        /// Localizable.xcstrings のキー
        var labelKey: String { "reminder_preset_\(rawValue)" }
    }

    /// 朝いちで思い出したい時刻
    static let morningHour = 9
    /// これより手前には置かない。押した直後に鳴るリマインダーは意味が無い
    static let minimumLeadMinutes = 5

    /// 候補ひとつぶんの時刻
    static func date(for preset: Preset, now: Date, calendar: Calendar = .current) -> Date {
        switch preset {
        case .tomorrowMorning:
            return at(hour: morningHour, dayOffset: 1, from: now, calendar: calendar)
        }
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

}
