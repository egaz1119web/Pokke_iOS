import XCTest

final class DomainGroupingTests: XCTestCase {

    private func item(_ id: String, _ url: String, _ savedAt: EpochMillis) -> StashItem {
        StashItem(id: id, url: url, title: id, savedAt: savedAt)
    }

    func testMajorServicesGetDisplayNames() {
        XCTAssertEqual(DomainGrouping.domainLabel(host: "twitter.com"), "Twitter")
        XCTAssertEqual(DomainGrouping.domainLabel(host: "x.com"), "Twitter")
        XCTAssertEqual(DomainGrouping.domainLabel(host: "youtu.be"), "YouTube")
        XCTAssertEqual(DomainGrouping.domainLabel(host: "www.instagram.com"), "Instagram")
    }

    func testSubdomainsFoldIntoTheSameService() {
        XCTAssertEqual(DomainGrouping.domainLabel(host: "m.youtube.com"), "YouTube")
        XCTAssertEqual(DomainGrouping.domainLabel(host: "mobile.twitter.com"), "Twitter")
    }

    func testUnknownDomainsUseTheirRegistrableName() {
        XCTAssertEqual(DomainGrouping.domainLabel(host: "example.com"), "Example")
        XCTAssertEqual(DomainGrouping.domainLabel(host: "www.asahi.co.jp"), "Asahi")
    }

    func testXComAndTwitterComFormOneGroup() {
        let items = [
            item("a", "https://twitter.com/a", 100),
            item("b", "https://x.com/b", 200),
            item("c", "https://youtu.be/c", 150),
        ]
        let groups = DomainGrouping.group(items)
        let twitter = groups.first { $0.label == "Twitter" }

        XCTAssertEqual(twitter?.items.count, 2)
        XCTAssertEqual(groups.count, 2)
    }

    /// twitter.com と x.com でロゴが2種類にならないこと
    func testSameServiceSharesOneLogoDomain() {
        XCTAssertEqual(DomainGrouping.logoDomain(host: "x.com"), "twitter.com")
        XCTAssertEqual(DomainGrouping.logoDomain(host: "mobile.twitter.com"), "twitter.com")
        XCTAssertEqual(DomainGrouping.logoDomain(host: "youtu.be"), "youtube.com")
        XCTAssertEqual(DomainGrouping.logoDomain(host: "m.youtube.com"), "youtube.com")
    }

    func testUnknownDomainsUseTheirRegistrableDomainForLogos() {
        XCTAssertEqual(DomainGrouping.logoDomain(host: "example.com"), "example.com")
        XCTAssertEqual(DomainGrouping.logoDomain(host: "blog.example.com"), "example.com")
        XCTAssertEqual(DomainGrouping.logoDomain(host: "www.asahi.co.jp"), "asahi.co.jp")
        XCTAssertEqual(DomainGrouping.logoDomain(host: "digital.asahi.co.jp"), "asahi.co.jp")
    }

    func testGroupCarriesItsLogoDomain() {
        let groups = DomainGrouping.group([item("a", "https://x.com/a", 100)])
        XCTAssertEqual(groups[0].domain, "twitter.com")
    }

    func testGroupsSortByCountAndItemsByRecency() {
        let items = [
            item("old", "https://x.com/old", 100),
            item("new", "https://x.com/new", 400),
            // 単独だが「1件のサービス」が1つだけなのでその他にはまとめない
            item("yt", "https://youtube.com/yt", 300),
        ]
        let groups = DomainGrouping.group(items)

        XCTAssertEqual(groups[0].label, "Twitter")
        XCTAssertEqual(groups[1].label, "YouTube")
        // グループ内は新しい順
        XCTAssertEqual(groups[0].items[0].id, "new")
        XCTAssertEqual(groups[0].items[1].id, "old")
    }

    func testEqualCountsAreBrokenByMostRecentSave() {
        let items = [
            item("x1", "https://x.com/1", 100),
            item("x2", "https://x.com/2", 200),
            item("y1", "https://youtube.com/1", 300),
            item("y2", "https://youtube.com/2", 400),
        ]
        let groups = DomainGrouping.group(items)

        XCTAssertEqual(groups[0].label, "YouTube")
        XCTAssertEqual(groups[1].label, "Twitter")
    }

    func testSingleItemServicesCollapseIntoOther() {
        let items = [
            item("x1", "https://x.com/1", 500),
            item("x2", "https://x.com/2", 400),
            item("a", "https://example.com/a", 300),
            item("b", "https://github.com/b", 200),
            item("c", "https://note.com/c", 100),
        ]
        let groups = DomainGrouping.group(items)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "Twitter")
        XCTAssertTrue(groups[1].isOther)
        XCTAssertEqual(groups[1].label, DomainGrouping.otherLabel)
        // その他の中も新しい順
        XCTAssertEqual(groups[1].items.map(\.id), ["a", "b", "c"])
    }

    func testOtherStaysLastEvenWhenItHasMoreItems() {
        let items = [
            item("x1", "https://x.com/1", 600),
            item("x2", "https://x.com/2", 500),
            item("a", "https://example.com/a", 400),
            item("b", "https://github.com/b", 300),
            item("c", "https://note.com/c", 200),
            item("d", "https://qiita.com/d", 100),
        ]
        let groups = DomainGrouping.group(items)

        // Twitterは2件、その他は4件だが、それでもその他が最後
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "Twitter")
        XCTAssertEqual(groups.last?.isOther, true)
        XCTAssertEqual(groups.last?.items.count, 4)
    }

    func testEverythingCollapsesWhenAllServicesHaveOneItem() {
        let items = [
            item("a", "https://example.com/a", 300),
            item("b", "https://github.com/b", 200),
            item("c", "https://note.com/c", 100),
        ]
        let groups = DomainGrouping.group(items)

        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isOther)
        XCTAssertEqual(groups[0].items.count, 3)
    }

    func testNoOtherGroupWhenOnlyOneServiceHasASingleItem() {
        let items = [
            item("x1", "https://x.com/1", 300),
            item("x2", "https://x.com/2", 200),
            item("a", "https://example.com/a", 100),
        ]
        let groups = DomainGrouping.group(items)

        XCTAssertFalse(groups.contains { $0.isOther })
        XCTAssertEqual(groups[1].label, "Example")
    }

    func testHostStripsWwwPrefix() {
        XCTAssertEqual(item("a", "https://www.asahi.co.jp/news", 1).host, "asahi.co.jp")
        XCTAssertEqual(item("b", "https://youtu.be/abc", 1).host, "youtu.be")
    }
}
