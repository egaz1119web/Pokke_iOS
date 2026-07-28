import XCTest

final class TodayPickTests: XCTestCase {

    private func item(
        _ id: String,
        _ savedAt: EpochMillis,
        archived: Bool = false,
        openCount: Int = 0
    ) -> StashItem {
        StashItem(
            id: id,
            url: "https://example.com/\(id)",
            title: id,
            savedAt: savedAt,
            archived: archived,
            openCount: openCount
        )
    }

    func testOldestUnreadIsChosen() {
        let items = [item("a", 300), item("b", 100), item("c", 200)]
        XCTAssertEqual(TodayPick.choose(items: items, skippedIds: [])?.id, "b")
    }

    func testSkippedReadAndArchivedAreExcluded() {
        let items = [
            item("skipped", 100),
            item("read", 200, openCount: 1),
            item("archived", 300, archived: true),
            item("ok", 400),
        ]
        XCTAssertEqual(TodayPick.choose(items: items, skippedIds: ["skipped"])?.id, "ok")
    }

    func testNilWhenNoCandidate() {
        XCTAssertNil(TodayPick.choose(items: [], skippedIds: []))
        XCTAssertNil(TodayPick.choose(items: [item("a", 1, openCount: 2)], skippedIds: []))
    }
}
