import XCTest

final class ReminderPlanTests: XCTestCase {

    /// 端末のタイムゾーンで結果が変わらないよう、テストは東京の暦で固定する
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// 東京時間の日時から Date を作る
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // MARK: - 候補

    func testTomorrowMorningIsTheNextDayAtNine() {
        let result = parts(ReminderPlan.date(for: .tomorrowMorning, now: date(2026, 8, 3, 22), calendar: calendar))

        XCTAssertEqual(result.day, 4)
        XCTAssertEqual(result.hour, ReminderPlan.morningHour)
        XCTAssertEqual(result.minute, 0)
    }

    func testEveryPresetIsInTheFuture() {
        let now = date(2026, 8, 3, 23, 30)
        for preset in ReminderPlan.Preset.allCases {
            XCTAssertGreaterThan(
                ReminderPlan.date(for: preset, now: now, calendar: calendar),
                now,
                "\(preset) が過去になっている"
            )
        }
    }

    // MARK: - 押し戻し・表示

    func testPastDatesArePushedForward() {
        let now = date(2026, 8, 3, 13)
        let stale = date(2026, 8, 1, 9)

        let result = ReminderPlan.notBefore(stale, now: now, calendar: calendar)

        XCTAssertGreaterThan(result, now)
    }

    /// 押した直後に鳴らないよう、今の時刻ちょうどでも少し先へ送る
    func testNowIsPushedPastTheMinimumLead() {
        let now = date(2026, 8, 3, 13)

        let result = ReminderPlan.notBefore(now, now: now, calendar: calendar)

        XCTAssertEqual(
            result.timeIntervalSince(now),
            TimeInterval(ReminderPlan.minimumLeadMinutes) * 60,
            accuracy: 1
        )
    }

    func testPendingOnlyCountsFutureReminders() {
        XCTAssertTrue(ReminderPlan.isPending(200, now: 100))
        XCTAssertFalse(ReminderPlan.isPending(100, now: 200))
        XCTAssertFalse(ReminderPlan.isPending(nil, now: 100))
    }
}
