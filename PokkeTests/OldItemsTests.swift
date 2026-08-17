import XCTest

final class OldItemsTests: XCTestCase {

    private let day: EpochMillis = 24 * 60 * 60 * 1000
    private let now: EpochMillis = 1_800_000_000_000

    private func item(
        _ id: String,
        daysAgo: Int,
        archived: Bool = false,
        favorite: Bool = false
    ) -> StashItem {
        StashItem(
            id: id,
            url: "https://example.com/\(id)",
            title: id,
            savedAt: now - EpochMillis(daysAgo) * day,
            archived: archived,
            favorite: favorite
        )
    }

    func testOnlyItemsOlderThanTheThresholdAreListed() {
        let items = [item("today", daysAgo: 0), item("six", daysAgo: 6), item("eight", daysAgo: 8)]

        XCTAssertEqual(OldItems.stale(items: items, now: now).map(\.id), ["eight"])
    }

    /// ちょうど7日は「1週間以上」に入る
    func testExactlyTheThresholdCounts() {
        XCTAssertEqual(OldItems.stale(items: [item("seven", daysAgo: 7)], now: now).count, 1)
    }

    func testOldestComesFirst() {
        let items = [item("b", daysAgo: 10), item("c", daysAgo: 30), item("a", daysAgo: 8)]

        XCTAssertEqual(OldItems.stale(items: items, now: now).map(\.id), ["c", "b", "a"])
    }

    /// アーカイブ済みも整理の対象。保存件数の上限はアーカイブしても減らないため
    func testArchivedItemsAreIncluded() {
        let items = [item("read", daysAgo: 20, archived: true), item("unread", daysAgo: 20)]

        XCTAssertEqual(Set(OldItems.stale(items: items, now: now).map(\.id)), ["read", "unread"])
    }

    /// お気に入りは何日たっても整理の一覧に出ない（＝まとめて消されない）
    func testFavoritesAreNeverListed() {
        let items = [
            item("keep", daysAgo: 300, favorite: true),
            item("keep-archived", daysAgo: 300, archived: true, favorite: true),
            item("drop", daysAgo: 300),
        ]

        XCTAssertEqual(OldItems.stale(items: items, now: now).map(\.id), ["drop"])
    }

    /// 声をかける対象はシートに並ぶものより狭い
    func testNoticeCountsFewerItemsThanTheSheetLists() {
        // 8日前は整理シートには並ぶが、声をかける対象ではない
        let items = [item("recent", daysAgo: 8), item("long", daysAgo: 40)]

        XCTAssertEqual(OldItems.stale(items: items, now: now).count, 2)
        XCTAssertEqual(OldItems.noticeCount(items: items, now: now), 1)
    }

    /// 片付けたぶんは声をかける件数に数えない
    func testArchivedItemsAreNotCountedForTheNotice() {
        let items = [
            item("archived", daysAgo: 40, archived: true),
            item("favorite", daysAgo: 40, favorite: true),
            item("piled", daysAgo: 40),
        ]

        // シートには枠を空けるためアーカイブ済みも並ぶ
        XCTAssertEqual(OldItems.stale(items: items, now: now).map(\.id), ["archived", "piled"])
        XCTAssertEqual(OldItems.noticeCount(items: items, now: now), 1)
    }

    /// 持っている量が増えるほど声をかけ始める件数も上がる
    func testNoticeThresholdGrowsWithTheLibrary() {
        XCTAssertEqual(OldItems.noticeThreshold(totalCount: 0), OldItems.noticeMinCount)
        XCTAssertEqual(OldItems.noticeThreshold(totalCount: 30), OldItems.noticeMinCount)
        XCTAssertEqual(OldItems.noticeThreshold(totalCount: 300), 100)
    }

    func testNoticeNeedsEnoughItems() {
        let threshold = OldItems.noticeThreshold(totalCount: 100)

        XCTAssertFalse(notice(staleCount: threshold - 1, totalCount: 100))
        XCTAssertTrue(notice(staleCount: threshold, totalCount: 100))
    }

    /// 閉じたら猶予のあいだは出さない。過ぎればまた出る
    func testNoticeStaysHiddenWhileSnoozed() {
        let firstSnooze = OldItems.snoozeStepsMs[0]

        XCTAssertFalse(notice(snoozedAt: now - firstSnooze + day, dismissCount: 1))
        XCTAssertTrue(notice(snoozedAt: now - firstSnooze, dismissCount: 1))
    }

    /// 閉じるたびに猶予が延びる
    func testSnoozeGrowsWithEachDismissal() {
        let firstSnooze = OldItems.snoozeStepsMs[0]

        // 1回目の猶予が明ける時刻でも、2回閉じたあとならまだ出ない
        XCTAssertTrue(notice(snoozedAt: now - firstSnooze, dismissCount: 1))
        XCTAssertFalse(notice(snoozedAt: now - firstSnooze, dismissCount: 2))
    }

    /// 猶予を使い切ったら二度と出さない
    func testNoticeNeverReturnsAfterTheLastStep() {
        let used = OldItems.snoozeStepsMs.count

        XCTAssertFalse(notice(snoozedAt: 0, dismissCount: used + 1))
        // どれだけ時間がたっても戻ってこない
        XCTAssertFalse(notice(snoozedAt: now - 3650 * day, dismissCount: used + 1))
    }

    /// 一度も閉じていなければ猶予なしで出る
    func testNoticeShowsWithoutSnoozeUntilDismissed() {
        XCTAssertTrue(notice(snoozedAt: 0, dismissCount: 0))
    }

    private func notice(
        staleCount: Int = 100,
        totalCount: Int = 100,
        snoozedAt: EpochMillis = 0,
        dismissCount: Int = 0
    ) -> Bool {
        OldItems.showsNotice(
            staleCount: staleCount,
            totalCount: totalCount,
            snoozedAt: snoozedAt,
            dismissCount: dismissCount,
            now: now
        )
    }
}
