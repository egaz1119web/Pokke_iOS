import XCTest

/// Android版 `CalendarExtractTest.kt` と同じ場面を見る。判定を両方で揃えておくため
final class CalendarExtractTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func at(_ year: Int, _ month: Int, _ day: Int) -> EpochMillis {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!.epochMillis
    }

    private func item(_ title: String, _ description: String? = nil, savedAt: EpochMillis? = nil) -> StashItem {
        StashItem(
            id: "a", url: "https://example.com/a", title: title, description: description,
            savedAt: savedAt ?? at(2026, 8, 20)
        )
    }

    private func parse(_ raw: String, _ item: StashItem) -> [CalendarCandidate] {
        CalendarExtract.parse(raw, item: item, timeZone: tokyo)
    }

    // 実機の「ガチャガチャ」コレクションに入っていた告知と同じ形
    private lazy var gacha = item(
        "しゅんドラン - Instagram: \"2026年8月発売最新ガシャポン 遊☆戯☆王 攻撃力ポーチコレクション 8月24日入荷！",
        "2026年8月発売最新ガシャポン\n\n遊☆戯☆王デュエルモンスターズ\n攻撃力ポーチコレクション\n\n8月24日入荷！"
    )

    func testReadsTheInstructedLine() {
        let result = parse("2026-08-24 | 攻撃力ポーチコレクション 入荷", gacha)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual([result[0].year, result[0].month, result[0].day], [2026, 8, 24])
        XCTAssertEqual(result[0].label, "攻撃力ポーチコレクション 入荷")
        XCTAssertTrue(result[0].allDay)
    }

    func testDropsDatesNotInTheText() {
        XCTAssertEqual(parse("2026-08-24 | 入荷\n2026-09-15 | 再販", gacha).map(\.day), [24])
    }

    func testReinfersYearNotInTheText() {
        // モデルが学習時点の年を付けてきても、本文に年が無ければ保存日基準にする
        let noYear = item("新作ガチャ", "12月3日入荷！", savedAt: at(2026, 10, 1))
        XCTAssertEqual(parse("2024-12-03 | 新作ガチャ 入荷", noYear).first?.year, 2026)
    }

    func testAnnouncementAcrossTheYearGoesToNextYear() {
        XCTAssertEqual(CalendarExtract.inferYear(month: 1, day: 10, savedAt: at(2026, 11, 20), timeZone: tokyo), 2027)
        // 少し前の告知を後から保存した場合は同じ年のまま
        XCTAssertEqual(CalendarExtract.inferYear(month: 8, day: 24, savedAt: at(2026, 9, 28), timeZone: tokyo), 2026)
    }

    func testReadsTimeAndLooseFormat() {
        let event = item("予約開始", "９月１日 10:00から予約受付")
        let c = parse("1. 2026/09/01 10:00：予約開始", event).first
        XCTAssertEqual(c?.hour, 10)
        XCTAssertEqual(c?.minute, 0)
        XCTAssertEqual(c?.label, "予約開始")
    }

    func testComposesLabelWhenMissingAndIgnoresNone() {
        XCTAssertTrue(parse("NONE", gacha).isEmpty)
        // アカウント名と、本文で日付と同じ行にある語から作る
        let c = parse("2026-08-24", gacha).first
        XCTAssertEqual(c?.label, "しゅんドラン 入荷")
        XCTAssertNil(c?.hour)
    }

    func testAllDayEndsAtNextMidnight() {
        let c = parse("2026-08-24 | 入荷", gacha)[0]
        XCTAssertEqual(c.endDate(timeZone: tokyo).timeIntervalSince(c.beginDate(timeZone: tokyo)), 24 * 60 * 60)
    }

    func testDateOnlyAnnouncementIsAllDayEvenIfModelAddsTime() {
        let release = item("新作フィギュア", "10/23 発売")
        let c = parse("2026-10-23 00:00 | 新作フィギュア 発売", release).first
        XCTAssertEqual(c?.allDay, true)
        XCTAssertEqual(c?.month, 10)
        XCTAssertEqual(c?.day, 23)
    }

    func testNumbersThatAreNotDatesAreIgnored() {
        // 10 と 23 は本文にあるが、日付ではない
        let notDate = item("限定グッズ", "先着10名様 23時まで受付 1500円")
        XCTAssertFalse(CalendarExtract.mayContainDate(notDate))
        XCTAssertTrue(parse("2026-10-23 | 限定グッズ", notDate).isEmpty)
    }

    func testUsesOnlyTimeWrittenNextToTheDate() {
        let event = item("イベント", "10月23日(金) 18時30分 開場")
        let c = parse("2026-10-23 | イベント 開場", event).first
        XCTAssertEqual(c?.hour, 18)
        XCTAssertEqual(c?.minute, 30)
    }

    func testFindsVariousDateForms() {
        func md(_ text: String) -> [[Int]] {
            CalendarExtract.findDates(CalendarExtract.normalize(text)).map { [$0.month, $0.day] }
        }
        XCTAssertEqual(md("１０／２３発売"), [[10, 23]])
        XCTAssertEqual(md("2026/10/23 release"), [[10, 23]])
        XCTAssertEqual(md("Out Oct 23rd"), [[10, 23]])
        XCTAssertEqual(md("on 23 October 2026"), [[10, 23]])
        XCTAssertEqual(md("10월 23일 발매"), [[10, 23]])
        XCTAssertEqual(CalendarExtract.findDates("2026年10月23日").first?.year, 2026)
    }

    func testSummaryGoesToNotesWithFallbackToDescription() {
        XCTAssertEqual(CalendarExtract.parseSummary("要約: 入荷の告知です。"), "入荷の告知です。")
        let notes = CalendarExtract.calendarNotes(summary: "入荷の告知です。", item: gacha)
        XCTAssertTrue(notes.hasPrefix("入荷の告知です。\n\n"))
        XCTAssertTrue(notes.hasSuffix(gacha.url))
        XCTAssertTrue(CalendarExtract.calendarNotes(summary: nil, item: gacha).hasPrefix("2026年8月発売最新ガシャポン"))
    }

    func testRecipeAmountsAreNotDates() {
        let recipe = item("簡単レシピ", "◆砂糖 小さじ1/2\n玉ねぎは1/4に切る\n塩 大さじ 1/3")
        XCTAssertFalse(CalendarExtract.mayContainDate(recipe))
        // 告知の日付は引き続き拾う
        XCTAssertTrue(CalendarExtract.mayContainDate(item("新作", "10/23(金)発売予定")))
    }

    func testStripsAccountNamesFromLabel() {
        let post = item("ポケモン情報NAKAYAMA【非公式】 / X", "GUのポケモンコラボ\n10/23(金)発売予定")
        // アカウント名しか無ければ、日付の横の語で何の日かを補う
        XCTAssertEqual(parse("2026-10-23 | ポケモン情報NAKAYAMA【非公式】 / X", post).first?.label, "ポケモン情報NAKAYAMA【非公式】 発売予定")
        let toy = item("タイトートイズ / X", "8月28日(金)から登場")
        XCTAssertEqual(parse("2026-08-28 | タイトートイズ / X プライズイベント開始", toy).first?.label, "プライズイベント開始")
        // 落とした結果「発売」だけになったら、誰の発売か分かるようアカウント名を前に付ける
        let book = item("ポケカブック / X", "30th CELEBRATION 最新情報\n8/24(月)発売")
        XCTAssertEqual(parse("2026-08-24 | ポケカブック / X 発売", book).first?.label, "ポケカブック 発売")
        // Android実機で「⚡予告⚡ 予告」になっていたGUの投稿
        let gu = item(
            "GU（ジーユー） / X",
            "⚡️予告⚡️\u{200B}\n\n自然の色合いを取り入れたコレクション✨\n\n10/23(金) 販売開始予定 pic.twitter.com/uWHWlsL8aJ"
        )
        XCTAssertEqual(parse("2026-10-23 | GU（ジーユー） / X 予告", gu).first?.label, "GU（ジーユー） 販売開始予定")
    }
}
