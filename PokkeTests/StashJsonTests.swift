import XCTest

final class StashJsonTests: XCTestCase {

    func testRoundTripPreservesState() {
        let state = StashState(
            items: [
                StashItem(
                    id: "1",
                    url: "https://example.com/article",
                    title: "テスト記事",
                    siteName: "Example",
                    imageUrl: "https://example.com/og.png",
                    description: "この記事の要約",
                    collectionId: "c1",
                    tags: ["読み物", "tech"],
                    savedAt: 1_234_567_890,
                    archived: false,
                    openCount: 2,
                    lastOpenedAt: 1_234_567_999,
                    updatedAt: 1_234_568_500
                ),
                StashItem(id: "2", url: "https://foo.jp/", title: "foo.jp", savedAt: 42),
            ],
            collections: [
                StashCollection(id: "c1", name: "あとで読む", icon: "bookmark", colorIndex: 3, updatedAt: 999),
            ],
            events: [
                UsageEvent(type: UsageEvent.save, time: 100),
                UsageEvent(type: UsageEvent.open, time: 200),
            ],
            pickDate: "2026-07-20",
            pickSkippedIds: ["2"],
            deletedIds: ["old-1": 555, "old-2": 556]
        )

        XCTAssertEqual(StashJson.fromJson(StashJson.toJson(state)), state)
    }

    func testEmptyStateRoundTrips() {
        XCTAssertEqual(StashJson.fromJson(StashJson.toJson(StashState())), StashState())
    }

    func testLegacyJsonWithoutUpdatedAtIsReadable() {
        let legacy = """
        {"items":[{"id":"1","url":"https://example.com/","title":"旧データ",
        "siteName":null,"imageUrl":null,"collectionId":null,"tags":[],
        "savedAt":1234567890,"archived":false,"openCount":0,"lastOpenedAt":null}],
        "collections":[{"id":"c1","name":"あとで読む","emoji":"📚","colorIndex":3}],
        "events":[],"pickDate":"2026-07-20","pickSkippedIds":[]}
        """

        let restored = StashJson.fromJson(legacy)

        // updatedAt が無ければ savedAt を最終更新時刻とみなす
        XCTAssertEqual(restored?.items.first?.updatedAt, 1_234_567_890)
        XCTAssertEqual(restored?.collections.first?.updatedAt, 0)
        XCTAssertEqual(restored?.deletedIds, [:])
        // description 導入前のデータはキー自体が無い
        XCTAssertNil(restored?.items.first?.description)
        // 絵文字は線画アイコンの識別子に読み替える
        XCTAssertEqual(restored?.collections.first?.icon, "bookmark")
    }

    func testLegacyEmojiWithoutAMatchingIconFallsBackToTheDefault() {
        let legacy = """
        {"items":[],"collections":[
          {"id":"c1","name":"走る","emoji":"🏃","colorIndex":0},
          {"id":"c2","name":"ごはん","emoji":"🍳","colorIndex":1}
        ],"events":[],"pickDate":"","pickSkippedIds":[]}
        """

        let icons = StashJson.fromJson(legacy)?.collections.map(\.icon)

        XCTAssertEqual(icons, [CollectionIcons.default, "utensils"])
    }

    /// Android版が書いたJSONをそのまま読めること（Firestoreドキュメントを共有するため）
    func testAndroidProducedJsonIsReadable() {
        let android = """
        {"items":[{"id":"abc","url":"https://zenn.dev/x","title":"記事","siteName":"Zenn",
        "imageUrl":"https://zenn.dev/og.png","description":"リード文","collectionId":null,"tags":["swift"],
        "savedAt":1750000000000,"archived":true,"openCount":3,"lastOpenedAt":1750000009999,
        "updatedAt":1750000010000}],
        "collections":[{"id":"c1","name":"技術","icon":"bulb","colorIndex":2,"updatedAt":1750000000000}],
        "events":[{"type":"save","time":1750000000000}],
        "pickDate":"2026-07-26","pickSkippedIds":["abc"],"deletedIds":{"gone":1749999999999}}
        """

        let state = StashJson.fromJson(android)
        let item = state?.items.first

        XCTAssertEqual(item?.url, "https://zenn.dev/x")
        XCTAssertEqual(item?.tags, ["swift"])
        XCTAssertEqual(item?.archived, true)
        XCTAssertEqual(item?.openCount, 3)
        XCTAssertEqual(item?.updatedAt, 1_750_000_010_000)
        XCTAssertEqual(item?.description, "リード文")
        XCTAssertEqual(state?.collections.first?.icon, "bulb")
        XCTAssertEqual(state?.collections.first?.colorIndex, 2)
        XCTAssertEqual(state?.events.first?.type, UsageEvent.save)
        XCTAssertEqual(state?.deletedIds["gone"], 1_749_999_999_999)
    }

    func testInvalidJsonReturnsNil() {
        XCTAssertNil(StashJson.fromJson("これはJSONではない"))
    }
}
