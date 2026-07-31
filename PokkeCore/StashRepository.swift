import Combine
import Foundation

/// `StashRepository.addLink(_:)` の結果
enum AddLinkResult {
    /// 保存できた。同じURLが既にあった場合は、増やさずにその1件を返す
    case saved(StashItem)
    /// URLとして読めなかった
    case invalidUrl
    /// 保存件数が上限に達している
    case limitReached

    var savedItem: StashItem? {
        if case let .saved(item) = self { return item }
        return nil
    }
}

/// アプリ全データの保管庫。App Groupコンテナの stash.json にJSONで永続化する。
/// デモ規模なので全件メモリ保持＋都度書き出しのシンプル構成。
@MainActor
final class StashRepository: ObservableObject {

    static let shared = StashRepository()

    /// 保存できるリンクの上限。
    ///
    /// 実質の制限はクラウド同期のドキュメントサイズ（FirestoreSyncの900KB）で、
    /// 1件あたりJSONで最悪2.5KBほどになる（og:descriptionが600文字上限のため）。
    /// 300件なら最悪ケースでも枠に収まる。アーカイブしてもファイルは軽くならないので、
    /// 数えるのはアーカイブ済みも含めた全件。
    static let maxItems = 300

    /// 残りがこの件数を切ったら、上限が近いことをホームで知らせる
    static let limitWarningRemaining = 20

    @Published private(set) var state = StashState()

    private var loaded = false

    private init() {}

    func initialize() {
        guard !loaded else { return }
        loaded = true
        if let stored = StashStore.read() { state = stored }
        refreshPickDateIfNeeded()
    }

    private func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 日付が変わっていたらスキップ履歴をリセット
    func refreshPickDateIfNeeded() {
        let today = today()
        if state.pickDate != today {
            mutate { $0.pickDate = today; $0.pickSkippedIds = [] }
        }
    }

    /// 今日のTodayPick。未読ゼロならnil
    func currentPick() -> StashItem? {
        TodayPick.choose(items: state.items, skippedIds: state.pickSkippedIds)
    }

    func skipPick(itemId: String) {
        mutate { $0.pickSkippedIds.append(itemId) }
    }

    /// URLを保存。タイトル等はまず仮置きし、バックグラウンドでOGPを取得して差し替える
    @discardableResult
    func addLink(_ url: String) -> AddLinkResult {
        guard let normalized = Self.normalizeUrl(url) else { return .invalidUrl }
        // 同一URLは重複保存しない。件数が増えないので上限判定より先に見る
        if let existing = state.items.first(where: { $0.url == normalized }) { return .saved(existing) }
        guard state.items.count < Self.maxItems else { return .limitReached }

        let item = StashItem(
            id: UUID().uuidString,
            url: normalized,
            title: Self.displayFallbackTitle(normalized),
            savedAt: nowMillis()
        )
        mutate {
            $0.items.insert(item, at: 0)
            $0.events.append(UsageEvent(type: UsageEvent.save, time: item.savedAt))
        }
        Task { await fetchMetadata(for: item.id, url: normalized) }
        return .saved(item)
    }

    /// 上限まであと何件か。0なら満杯
    var remainingSlots: Int { max(0, Self.maxItems - state.items.count) }

    /// サムネイル・本文がまだ空のアイテムを取得し直す。
    ///
    /// 共有拡張は別プロセスで短命なのでOGPを取らずURLだけ保存する。その分と、
    /// 保存時に取得できなかった（通信断・UAを弾かれた等）分をここで埋める。
    /// 全件叩かないよう件数を絞る。
    func retryMissingMetadata(limit: Int = 20) {
        let targets = state.items
            .filter { $0.imageUrl == nil && $0.description == nil }
            .sorted { $0.savedAt > $1.savedAt }
            .prefix(limit)
        for item in targets {
            Task { await fetchMetadata(for: item.id, url: item.url) }
        }
    }

    /// 詳細画面からの手動再取得
    func refetchMetadata(itemId: String) {
        guard let item = state.items.first(where: { $0.id == itemId }) else { return }
        Task { await fetchMetadata(for: item.id, url: item.url) }
    }

    /// メタデータを取得して1件に反映する。取得できなければ何もしない
    private func fetchMetadata(for id: String, url: String) async {
        guard let meta = await MetadataFetcher.fetch(url) else { return }
        mutate { s in
            // 取得は非同期なので、待っている間に消えている・並びが変わっていることがある
            guard let index = s.items.firstIndex(where: { $0.id == id }) else { return }
            s.items[index].title = meta.title ?? s.items[index].title
            s.items[index].siteName = meta.siteName ?? s.items[index].siteName
            s.items[index].imageUrl = meta.imageUrl ?? s.items[index].imageUrl
            s.items[index].description = meta.description ?? s.items[index].description
            // 取得したサムネ・タイトルも他端末へ配りたいので更新時刻を進める
            s.items[index].updatedAt = nowMillis()
        }
    }

    /// リモート（Firestore）の状態をローカルへ取り込む。
    /// 上書きではなくマージなので、この端末にしか無いデータが消えることはない。
    /// 取り込みで内容が変わらなかった場合は何もしない（同期ループ防止）。
    @discardableResult
    func mergeRemote(_ remote: StashState) -> StashState {
        let merged = StashMerge.merge(local: state, remote: remote, now: nowMillis())
        if merged != state { mutate { $0 = merged } }
        return merged
    }

    /// 共有拡張が別プロセスで書き足した分を取り込む。フォアグラウンド復帰時に呼ぶ。
    /// 上書きではなく同じマージ規則を通すので、どちらの変更も失われない。
    func reloadFromDisk() {
        guard let onDisk = StashStore.read(), onDisk != state else { return }
        mergeRemote(onDisk)
        retryMissingMetadata()
    }

    func updateItem(_ updated: StashItem) {
        mutate { s in
            guard let index = s.items.firstIndex(where: { $0.id == updated.id }) else { return }
            s.items[index] = updated
            s.items[index].updatedAt = nowMillis()
        }
    }

    func deleteItem(id: String) {
        let now = nowMillis()
        mutate { s in
            s.items.removeAll { $0.id == id }
            s.deletedIds[id] = now
        }
    }

    func setArchived(id: String, archived: Bool) {
        mutate { s in
            guard let index = s.items.firstIndex(where: { $0.id == id }) else { return }
            s.items[index].archived = archived
            s.items[index].updatedAt = nowMillis()
        }
    }

    /// ブラウザで開いた＝再訪としてカウント
    func markOpened(id: String) {
        let now = nowMillis()
        mutate { s in
            guard let index = s.items.firstIndex(where: { $0.id == id }) else { return }
            s.items[index].openCount += 1
            s.items[index].lastOpenedAt = now
            s.items[index].updatedAt = now
            s.events.append(UsageEvent(type: UsageEvent.open, time: now))
        }
    }

    @discardableResult
    func addCollection(name: String, icon: String, colorIndex: Int) -> StashCollection {
        let collection = StashCollection(
            id: UUID().uuidString,
            name: name,
            icon: icon,
            colorIndex: colorIndex,
            updatedAt: nowMillis()
        )
        mutate { $0.collections.append(collection) }
        return collection
    }

    /// 名前・アイコン・色の編集。更新時刻を進めて他端末にも配る
    func updateCollection(_ updated: StashCollection) {
        mutate { s in
            guard let index = s.collections.firstIndex(where: { $0.id == updated.id }) else { return }
            s.collections[index] = updated
            s.collections[index].updatedAt = nowMillis()
        }
    }

    func deleteCollection(id: String) {
        let now = nowMillis()
        mutate { s in
            s.collections.removeAll { $0.id == id }
            for index in s.items.indices where s.items[index].collectionId == id {
                s.items[index].collectionId = nil
                s.items[index].updatedAt = now
            }
            s.deletedIds[id] = now
        }
    }

    /// http(s)のURLだけ受け付け、httpはhttpsへ格上げする
    static func normalizeUrl(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: "https?://\\S+") else { return nil }
        let ns = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length))
        else { return nil }

        var url = ns.substring(with: match.range)
        if url.hasPrefix("http://") { url = "https://" + url.dropFirst("http://".count) }
        while let last = url.last, ".,)」。".contains(last) { url.removeLast() }
        return url.isEmpty ? nil : url
    }

    /// OGP取得前の仮タイトル（スキーム部分を落としただけのURL）
    static func displayFallbackTitle(_ url: String) -> String {
        if url.hasPrefix("https://") { return String(url.dropFirst("https://".count)) }
        if url.hasPrefix("http://") { return String(url.dropFirst("http://".count)) }
        return url
    }

    /// 保存した内容をすべて捨てる。設定画面の削除（アカウント削除・端末のデータ削除）で使う。
    ///
    /// `mutate` を通さないのは、空にしたJSONを書き戻すのではなくファイルごと消したいため
    func deleteEverything() {
        state = StashState()
        StashStore.clear()
    }

    private func mutate(_ transform: (inout StashState) -> Void) {
        var next = state
        transform(&next)
        guard next != state else { return }
        state = next
        StashStore.write(next)
    }
}
