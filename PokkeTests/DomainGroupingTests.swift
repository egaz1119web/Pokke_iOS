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

    func testGroupsAndItemsAreSortedNewestFirst() {
        let items = [
            item("old", "https://x.com/old", 100),
            item("new", "https://x.com/new", 400),
            item("yt", "https://youtube.com/yt", 300),
        ]
        let groups = DomainGrouping.group(items)

        // 最新(400)を含むTwitterが先頭
        XCTAssertEqual(groups[0].label, "Twitter")
        XCTAssertEqual(groups[1].label, "YouTube")
        // グループ内は新しい順
        XCTAssertEqual(groups[0].items[0].id, "new")
        XCTAssertEqual(groups[0].items[1].id, "old")
    }

    func testHostStripsWwwPrefix() {
        XCTAssertEqual(item("a", "https://www.asahi.co.jp/news", 1).host, "asahi.co.jp")
        XCTAssertEqual(item("b", "https://youtu.be/abc", 1).host, "youtu.be")
    }
}
