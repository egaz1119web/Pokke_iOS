import XCTest

final class StashMergeTests: XCTestCase {

    private let now: EpochMillis = 1_700_000_000_000

    private func item(
        _ id: String,
        title: String? = nil,
        updatedAt: EpochMillis? = nil,
        collectionId: String? = nil,
        archived: Bool = false
    ) -> StashItem {
        let at = updatedAt ?? now
        return StashItem(
            id: id,
            url: "https://example.com/\(id)",
            title: title ?? "t-\(id)",
            collectionId: collectionId,
            savedAt: at,
            archived: archived,
            updatedAt: at
        )
    }

    func testBothDevicesKeepTheirOwnItems() {
        let local = StashState(items: [item("a")])
        let remote = StashState(items: [item("b")])

        let merged = StashMerge.merge(local: local, remote: remote, now: now)

        XCTAssertEqual(Set(merged.items.map(\.id)), ["a", "b"])
    }

    func testEmptyLocalDoesNotWipeRemoteOnFreshSignIn() {
        let merged = StashMerge.merge(
            local: StashState(),
            remote: StashState(items: [item("a"), item("b")]),
            now: now
        )

        XCTAssertEqual(merged.items.count, 2)
    }

    func testNewerUpdatedAtWins() {
        let local = StashState(items: [item("a", title: "古い", updatedAt: now - 5_000)])
        let remote = StashState(items: [item("a", title: "新しい", updatedAt: now)])

        XCTAssertEqual(StashMerge.merge(local: local, remote: remote, now: now).items.first?.title, "新しい")
        // 引数の順番を入れ替えても結果は同じ
        XCTAssertEqual(StashMerge.merge(local: remote, remote: local, now: now).items.first?.title, "新しい")
    }

    func testDeletedOnAnotherDeviceStaysDeleted() {
        let local = StashState(items: [item("a", updatedAt: now - 10_000)])
        let remote = StashState(deletedIds: ["a": now - 5_000])

        let merged = StashMerge.merge(local: local, remote: remote, now: now)

        XCTAssertTrue(merged.items.isEmpty)
        XCTAssertEqual(merged.deletedIds["a"], now - 5_000)
    }

    func testEditAfterDeleteResurrectsTheItem() {
        let local = StashState(items: [item("a", title: "編集後", updatedAt: now)])
        let remote = StashState(deletedIds: ["a": now - 5_000])

        let merged = StashMerge.merge(local: local, remote: remote, now: now)

        XCTAssertEqual(merged.items.first?.title, "編集後")
    }

    func testOldTombstonesAreDropped() {
        let old = now - StashMerge.tombstoneTtlMs - 1
        let merged = StashMerge.merge(
            local: StashState(deletedIds: ["a": old]),
            remote: StashState(),
            now: now
        )

        XCTAssertNil(merged.deletedIds["a"])
    }

    func testCollectionsMergeAndDeletionPropagates() {
        let local = StashState(collections: [
            StashCollection(id: "c1", name: "レシピ", icon: "utensils", colorIndex: 0, updatedAt: now - 1000),
            StashCollection(id: "c2", name: "映画", icon: "clap", colorIndex: 1, updatedAt: now - 900),
        ])
        let remote = StashState(deletedIds: ["c2": now - 100])

        let merged = StashMerge.merge(local: local, remote: remote, now: now)

        XCTAssertEqual(merged.collections.map(\.id), ["c1"])
    }

    func testEventsAreDedupedAndExpired() {
        let shared = UsageEvent(type: UsageEvent.save, time: now - 1000)
        let local = StashState(events: [shared, UsageEvent(type: UsageEvent.open, time: now - 500)])
        let remote = StashState(events: [
            shared,
            UsageEvent(type: UsageEvent.save, time: now - StashMerge.eventTtlMs - 1),
        ])

        let merged = StashMerge.merge(local: local, remote: remote, now: now)

        XCTAssertEqual(merged.events.map(\.time), [now - 1000, now - 500])
    }

    func testTodayPickTakesTheNewerDate() {
        let local = StashState(pickDate: "2026-07-25", pickSkippedIds: ["a"])
        let remote = StashState(
            items: [item("b")],
            pickDate: "2026-07-26",
            pickSkippedIds: ["b"]
        )

        let merged = StashMerge.merge(local: local, remote: remote, now: now)

        XCTAssertEqual(merged.pickDate, "2026-07-26")
        XCTAssertEqual(merged.pickSkippedIds, ["b"])
    }

    func testSameDayMergesSkippedIds() {
        let items = [item("a"), item("b")]
        let local = StashState(items: items, pickDate: "2026-07-26", pickSkippedIds: ["a"])
        let remote = StashState(items: items, pickDate: "2026-07-26", pickSkippedIds: ["b"])

        let merged = StashMerge.merge(local: local, remote: remote, now: now)

        XCTAssertEqual(Set(merged.pickSkippedIds), ["a", "b"])
    }

    func testTwoDevicesConvergeToTheSameState() {
        var deviceA = StashState(items: [item("a", updatedAt: now - 3000)])
        var deviceB = StashState(items: [item("b", updatedAt: now - 2000)])

        // A が送信 → B が受信してマージ → B が送信 → A が受信してマージ
        let cloud1 = deviceA
        deviceB = StashMerge.merge(local: deviceB, remote: cloud1, now: now)
        let cloud2 = deviceB
        deviceA = StashMerge.merge(local: deviceA, remote: cloud2, now: now)

        XCTAssertEqual(deviceA, deviceB)
        XCTAssertEqual(Set(deviceA.items.map(\.id)), ["a", "b"])
    }

    func testMergeIsIdempotent() {
        let local = StashState(
            items: [item("a"), item("b", updatedAt: now - 100)],
            collections: [StashCollection(id: "c1", name: "レシピ", icon: "utensils", colorIndex: 0, updatedAt: now)],
            deletedIds: ["z": now - 50]
        )
        let remote = StashState(items: [item("b", title: "更新", updatedAt: now)])

        let once = StashMerge.merge(local: local, remote: remote, now: now)
        let twice = StashMerge.merge(local: once, remote: remote, now: now)

        XCTAssertEqual(once, twice)
    }
}
