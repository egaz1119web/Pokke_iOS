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

    func testThreeHoursLaterKeepsTheMinuteAndDropsSeconds() {
        // 2026-08-03(月) 13:20
        let now = date(2026, 8, 3, 13, 20).addingTimeInterval(45)

        let result = parts(ReminderPlan.date(for: .inThreeHours, now: now, calendar: calendar))

        XCTAssertEqual(result.hour, 16)
        XCTAssertEqual(result.minute, 20)
    }

    func testTomorrowMorningIsTheNextDayAtNine() {
        let result = parts(ReminderPlan.date(for: .tomorrowMorning, now: date(2026, 8, 3, 22), calendar: calendar))

        XCTAssertEqual(result.day, 4)
        XCTAssertEqual(result.hour, ReminderPlan.morningHour)
        XCTAssertEqual(result.minute, 0)
    }

    /// 月曜に押したら、その週の土曜
    func testWeekendIsTheNextSaturday() {
        let result = parts(ReminderPlan.date(for: .weekend, now: date(2026, 8, 3, 13), calendar: calendar))

        XCTAssertEqual(result.day, 8)
        XCTAssertEqual(result.hour, ReminderPlan.weekendHour)
    }

    /// 土曜の朝にまだ時間があるなら、来週まで待たせない
    func testWeekendCanBeToday() {
        let result = parts(ReminderPlan.date(for: .weekend, now: date(2026, 8, 8, 7), calendar: calendar))

        XCTAssertEqual(result.day, 8)
        XCTAssertEqual(result.hour, ReminderPlan.weekendHour)
    }

    /// 土曜でも時間を過ぎていれば次の土曜
    func testWeekendMovesToNextWeekWhenTodayIsOver() {
        let result = parts(ReminderPlan.date(for: .weekend, now: date(2026, 8, 8, 18), calendar: calendar))

        XCTAssertEqual(result.day, 15)
    }

    func testNextWeekIsSevenDaysLaterInTheMorning() {
        let result = parts(ReminderPlan.date(for: .nextWeek, now: date(2026, 8, 3, 13), calendar: calendar))

        XCTAssertEqual(result.day, 10)
        XCTAssertEqual(result.hour, ReminderPlan.morningHour)
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

    // MARK: - AIの答えの丸め

    func testAiHoursBecomeAConcreteTime() {
        let now = date(2026, 8, 3, 10)

        let result = parts(ReminderPlan.resolve(hoursFromNow: 5, now: now, calendar: calendar))

        XCTAssertEqual(result.day, 3)
        XCTAssertEqual(result.hour, 15)
    }

    /// 0時間後・数万時間後のような答えも返ってくるので、必ず幅に収める
    func testAiHoursAreClamped() {
        let now = date(2026, 8, 3, 10)

        let tooSoon = ReminderPlan.resolve(hoursFromNow: 0, now: now, calendar: calendar)
        XCTAssertGreaterThan(tooSoon, now)

        let tooFar = ReminderPlan.resolve(hoursFromNow: 100_000, now: now, calendar: calendar)
        let limit = now.addingTimeInterval(TimeInterval(ReminderPlan.maxDelayDays) * 24 * 60 * 60)
        // 夜を避けるぶん少し動くので、上限から1日以上は離れない
        XCTAssertLessThanOrEqual(tooFar.timeIntervalSince(limit), 24 * 60 * 60)
    }

    /// 深夜に当たったら朝へ寄せる（起こさない）
    func testLateNightIsMovedToTheMorning() {
        let now = date(2026, 8, 3, 20)

        // 20時 + 6時間 = 翌2時
        let result = parts(ReminderPlan.resolve(hoursFromNow: 6, now: now, calendar: calendar))

        XCTAssertEqual(result.day, 4)
        XCTAssertEqual(result.hour, ReminderPlan.morningHour)
    }

    func testLateEveningIsMovedToTheNextMorning() {
        let now = date(2026, 8, 3, 20)

        // 20時 + 3時間 = 23時 → 翌朝
        let result = parts(ReminderPlan.resolve(hoursFromNow: 3, now: now, calendar: calendar))

        XCTAssertEqual(result.day, 4)
        XCTAssertEqual(result.hour, ReminderPlan.morningHour)
    }

    /// 夜を避けた結果が現在より手前に来てはいけない
    func testAdjustedTimeNeverLandsInThePast() {
        let now = date(2026, 8, 4, 3)

        let result = ReminderPlan.resolve(hoursFromNow: 1, now: now, calendar: calendar)

        XCTAssertGreaterThan(result, now)
        XCTAssertEqual(parts(result).hour, ReminderPlan.morningHour)
    }

    func testPastDatesArePushedForward() {
        let now = date(2026, 8, 3, 13)
        let stale = date(2026, 8, 1, 9)

        let result = ReminderPlan.notBefore(stale, now: now, calendar: calendar)

        XCTAssertGreaterThan(result, now)
    }

    // MARK: - 表示・プロンプト

    func testPendingOnlyCountsFutureReminders() {
        XCTAssertTrue(ReminderPlan.isPending(200, now: 100))
        XCTAssertFalse(ReminderPlan.isPending(100, now: 200))
        XCTAssertFalse(ReminderPlan.isPending(nil, now: 100))
    }

    func testReasonIsCollapsedAndTruncated() {
        XCTAssertEqual(ReminderPlan.refineReason("  夜に  読むと\nよさそう "), "夜に 読むと よさそう")
        XCTAssertNil(ReminderPlan.refineReason("   \n "))
        XCTAssertEqual(ReminderPlan.refineReason(String(repeating: "あ", count: 100))?.count, 61)
    }

    /// プロンプトに曜日と時刻が入っていないと「週末に」の判断ができない
    func testPromptCarriesTheCurrentTimeAndTheLink() {
        let item = StashItem(
            id: "1",
            url: "https://example.com/a",
            title: "夏フェスの持ち物",
            siteName: "Example",
            description: "8月15日の開催に向けて",
            tags: ["おでかけ"],
            savedAt: date(2026, 8, 1, 9).epochMillis
        )

        let prompt = ReminderPlan.buildPrompt(
            instruction: "instruction",
            item: item,
            now: date(2026, 8, 3, 13, 5).epochMillis,
            calendar: calendar
        )

        XCTAssertTrue(prompt.contains("2026-08-03 13:05 (Monday)"), prompt)
        XCTAssertTrue(prompt.contains("title: 夏フェスの持ち物"), prompt)
        XCTAssertTrue(prompt.contains("saved: 2026-08-01"), prompt)
        XCTAssertTrue(prompt.contains("tags: おでかけ"), prompt)
        XCTAssertTrue(prompt.contains("note: 8月15日の開催に向けて"), prompt)
    }
}
