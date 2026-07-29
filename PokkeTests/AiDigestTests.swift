import XCTest

final class AiDigestTests: XCTestCase {

    private let now: EpochMillis = 1_800_000_000_000 // 2027-01-15 頃

    private func daysAgo(_ days: Int) -> EpochMillis { now - EpochMillis(days) * 86_400_000 }

    private func item(
        _ id: String,
        _ title: String,
        savedAt: EpochMillis? = nil,
        description: String? = nil,
        tags: [String] = [],
        url: String? = nil
    ) -> StashItem {
        StashItem(
            id: id,
            url: url ?? "https://example.com/\(id)",
            title: title,
            description: description,
            tags: tags,
            savedAt: savedAt ?? now
        )
    }

    // MARK: - selectRelevant

    func testLinksSharingWordsWithTheQuestionAreChosenFirst() {
        let items = [
            item("a", "週末の献立メモ", savedAt: daysAgo(1)),
            item("b", "Kotlin コルーチン入門", savedAt: daysAgo(2)),
            item("c", "旅行の持ち物リスト", savedAt: daysAgo(3)),
        ]
        let selected = AiDigest.selectRelevant(items: items, question: "コルーチンの記事あった？", limit: 1)
        XCTAssertEqual(selected.map(\.id), ["b"])
    }

    func testEnglishQuestionsMatchBodyAndTags() {
        let items = [
            item("a", "Dinner ideas"),
            item("b", "Getting started", tags: ["kotlin"]),
            item("c", "Some post", description: "A guide to kotlin coroutines"),
        ]
        let selected = AiDigest.selectRelevant(items: items, question: "anything about kotlin?", limit: 2)
        // タグの一致（3点）が本文の一致（1点）より上に来る
        XCTAssertEqual(selected.map(\.id).sorted(), ["b", "c"])
        XCTAssertFalse(selected.map(\.id).contains("a"))
    }

    func testNoMatchFallsBackToNewestWithoutBeingEmpty() {
        let items = [
            item("old", "むかしの記事", savedAt: daysAgo(30)),
            item("new", "きのうの記事", savedAt: daysAgo(1)),
        ]
        let selected = AiDigest.selectRelevant(items: items, question: "最近どう？", limit: 1)
        XCTAssertEqual(selected.map(\.id), ["new"])
    }

    func testMatchesAreNotPaddedWithRecentWhenSlotsAreLeftOver() {
        let items = [
            item("hit", "味噌ラーメンのレシピ", savedAt: daysAgo(20)),
            item("noise1", "全然関係ない話", savedAt: daysAgo(1)),
            item("noise2", "これも関係ない", savedAt: daysAgo(2)),
        ]
        // 無関係な記事を混ぜると、小さいモデルはそちらに引っ張られる
        let selected = AiDigest.selectRelevant(items: items, question: "ラーメン", limit: 12)
        XCTAssertEqual(selected.map(\.id), ["hit"])
    }

    func testTiesBreakByNewest() {
        let items = [
            item("a", "レシピ 和食", savedAt: daysAgo(10)),
            item("b", "レシピ 中華", savedAt: daysAgo(2)),
            item("c", "レシピ 洋食", savedAt: daysAgo(6)),
        ]
        let selected = AiDigest.selectRelevant(items: items, question: "レシピ", limit: 3)
        XCTAssertEqual(selected.map(\.id), ["b", "c", "a"])
    }

    func testOldMatchStillComesFirst() {
        var items = (1...30).map { item("i\($0)", "保存した記事 \($0)", savedAt: daysAgo($0)) }
        items.append(item("ramen", "味噌ラーメンのレシピ", savedAt: daysAgo(400)))
        // 「記事」は全件に当たるので絞り込みには使われず、「ラーメン」だけが効く
        let selected = AiDigest.selectRelevant(items: items, question: "ラーメンの記事あった？")
        XCTAssertEqual(selected.map(\.id), ["ramen"])
    }

    func testCommonTermsOnlyGivesUpNarrowing() {
        let items = (1...30).map { item("i\($0)", "保存した記事 \($0)", savedAt: daysAgo($0)) }
        // ここで語を全部捨てると一致ゼロ扱いになってしまう。捨てずに新しい順で拾う
        let selected = AiDigest.selectRelevant(items: items, question: "記事ある？")
        XCTAssertEqual(selected.count, AiDigest.maxItems)
        XCTAssertEqual(selected.first?.id, "i1")
    }

    func testSelectionIsCappedAtTheLimit() {
        let items = (1...40).map { item("i\($0)", "記事 \($0)", savedAt: daysAgo($0)) }
        XCTAssertEqual(AiDigest.selectRelevant(items: items, question: "記事").count, AiDigest.maxItems)
    }

    func testEmptyListDoesNotCrash() {
        XCTAssertTrue(AiDigest.selectRelevant(items: [], question: "なにかある？").isEmpty)
    }

    // MARK: - buildContext

    func testContextIncludesTitleSiteSavedTagsAndNote() {
        let entry = item(
            "a",
            "コルーチン入門",
            savedAt: daysAgo(3),
            description: "非同期処理の\n基本を解説",
            tags: ["kotlin", "android"],
            url: "https://zenn.dev/foo"
        )
        let context = AiDigest.buildContext(all: [entry], selected: [entry], now: now)
        XCTAssertTrue(context.contains("TODAY: "))
        XCTAssertTrue(context.contains("[1] コルーチン入門"))
        XCTAssertTrue(context.contains("site: zenn.dev"))
        XCTAssertTrue(context.contains("saved: "))
        XCTAssertTrue(context.contains("tags: kotlin, android"))
        // 改行はつぶして1行に収める。行が増えるとAIが別のリンクの情報と混ぜる
        XCTAssertTrue(context.contains("note: 非同期処理の 基本を解説"))
    }

    func testOverviewIsBuiltFromAllItemsEvenWhenNotAllAreDetailed() {
        let all = (1...200).map {
            item(
                "i\($0)",
                "記事 \($0)",
                savedAt: daysAgo($0),
                tags: $0 % 2 == 0 ? ["kotlin"] : [],
                url: $0 % 3 == 0 ? "https://youtube.com/\($0)" : "https://example.com/\($0)"
            )
        }
        let selected = AiDigest.selectRelevant(items: all, question: "なにか面白いのある？")
        let context = AiDigest.buildContext(all: all, selected: selected, now: now)

        // 詳しく渡せるのは12件でも、全体の件数・期間・傾向は正しく伝わる
        XCTAssertTrue(context.contains("TOTAL: 200 links saved between "))
        XCTAssertTrue(context.contains("UNREAD: 200"))
        XCTAssertTrue(context.contains("TOP SITES: example.com (134), youtube.com (66)"))
        XCTAssertTrue(context.contains("TOP TAGS: kotlin (100)"))
        // 一部しか見ていないことを明記しないと、全部を見たつもりで言い切る
        XCTAssertTrue(context.contains("DETAILS BELOW: 12 of them, picked for this question"))
    }

    func testOverviewSaysAllWhenEverythingIsDetailed() {
        let all = [item("a", "ひとつめ"), item("b", "ふたつめ")]
        let context = AiDigest.buildContext(all: all, selected: all, now: now)
        XCTAssertTrue(context.contains("DETAILS BELOW: all 2 of them"))
    }

    func testOverviewStillBuildsWhenScopeIsEmpty() {
        let context = AiDigest.buildContext(all: [], selected: [], now: now)
        XCTAssertTrue(context.contains("TODAY: "))
        XCTAssertFalse(context.contains("TOTAL: "))
    }

    func testContextIsCutOffWholeEntryAtATime() {
        let items = (1...AiDigest.maxItems).map {
            item(
                "i\($0)",
                String(repeating: "とても長いタイトル", count: 10),
                description: String(repeating: "本文", count: 200)
            )
        }
        let context = AiDigest.buildContext(all: items, selected: items, now: now)
        XCTAssertLessThanOrEqual(context.count, 2400)
        // 打ち切りは1件まるごと単位。半端に切れた行が残ると、AIが
        // 別のリンクの情報と混ぜてしまう
        let entries = count(matching: "\\[\\d+\\] ", in: context)
        XCTAssertEqual(entries, count(matching: "(?m)^ {2}site: ", in: context))
        XCTAssertEqual(entries, count(matching: "(?m)^ {2}note: ", in: context))
        XCTAssertTrue((1..<AiDigest.maxItems).contains(entries))
    }

    // MARK: - buildPrompt

    func testPromptOrdersInstructionContextThenQuestion() {
        let prompt = AiDigest.buildPrompt(
            instruction: "短く答えて",
            context: "TODAY: 2027-01-15\n\n[1] テスト\n",
            question: "  なにが保存されてる？  "
        )
        XCTAssertTrue(prompt.hasPrefix("短く答えて"))
        XCTAssertGreaterThan(
            prompt.range(of: "[1] テスト")!.lowerBound,
            prompt.range(of: "短く答えて")!.lowerBound
        )
        XCTAssertGreaterThan(
            prompt.range(of: "なにが保存されてる？")!.lowerBound,
            prompt.range(of: "[1] テスト")!.lowerBound
        )
        // 前後の空白は落として渡す
        XCTAssertFalse(prompt.contains("  なにが"))
    }

    // MARK: - refineTagSuggestions

    func testRefineDropsTagsAlreadyOnTheItem() {
        let refined = AiDigest.refineTagSuggestions(["kotlin", "android"], existing: ["kotlin"])
        XCTAssertEqual(refined, ["android"])
    }

    func testRefineSnapsSpellingVariantsToVocabulary() {
        // モデルが「android x」と返しても、既存語彙の綴り「androidx」に揃える
        let refined = AiDigest.refineTagSuggestions(["android x"], existing: [], vocabulary: ["androidx"])
        XCTAssertEqual(refined, ["androidx"])
    }

    func testRefinePrefersReusedTagsOverFreshOnes() {
        let refined = AiDigest.refineTagSuggestions(
            ["brand-new-tag", "kotlin"],
            existing: [],
            vocabulary: ["kotlin", "swift"]
        )
        XCTAssertEqual(refined, ["kotlin", "brand-new-tag"])
    }

    func testRefineCapsAtFourSuggestions() {
        let refined = AiDigest.refineTagSuggestions(["a", "b", "c", "d", "e"], existing: [])
        XCTAssertEqual(refined.count, AiDigest.maxTagSuggestions)
    }

    // MARK: - helpers

    private func count(matching pattern: String, in text: String) -> Int {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
