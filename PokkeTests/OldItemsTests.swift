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

    func testNoticeNeedsEnoughItems() {
        XCTAssertFalse(OldItems.showsNotice(staleCount: OldItems.noticeThreshold - 1, snoozedAt: 0, now: now))
        XCTAssertTrue(OldItems.showsNotice(staleCount: OldItems.noticeThreshold, snoozedAt: 0, now: now))
    }

    /// 閉じたら猶予のあいだは出さない。過ぎればまた出る
    func testNoticeStaysHiddenWhileSnoozed() {
        let justClosed = now - day
        XCTAssertFalse(OldItems.showsNotice(staleCount: 50, snoozedAt: justClosed, now: now))

        let longAgo = now - OldItems.snoozeMs - day
        XCTAssertTrue(OldItems.showsNotice(staleCount: 50, snoozedAt: longAgo, now: now))
    }
}
