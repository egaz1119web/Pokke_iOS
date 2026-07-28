import Foundation

/// ローカルとリモートの状態を突き合わせて1つにまとめる。
///
/// ドキュメント丸ごとの「最終書き込み優先」だと、2台目で編集した瞬間に片方の変更が消える。
/// ここではレコード単位で updatedAt を比べ、削除は墓標(deletedIds)で表現することで、
/// どちらの端末から見ても同じ結果に収束するようにしている（順序に依存しない・冪等）。
enum StashMerge {

    /// 墓標の保持期間。これを過ぎたら墓標自体を捨てる（長期オフライン端末の復活は諦める）
    static let tombstoneTtlMs: EpochMillis = 90 * 24 * 60 * 60 * 1000

    /// イベント履歴の保持期間。Firestoreの1ドキュメント上限に当たらないよう古い分は捨てる
    static let eventTtlMs: EpochMillis = 90 * 24 * 60 * 60 * 1000

    static func merge(local: StashState, remote: StashState, now: EpochMillis) -> StashState {
        // 墓標は両者の和集合。同じIDなら新しい削除時刻を採用する
        var tombstones: [String: EpochMillis] = [:]
        for id in Set(local.deletedIds.keys).union(remote.deletedIds.keys) {
            let at = max(local.deletedIds[id] ?? 0, remote.deletedIds[id] ?? 0)
            if now - at <= tombstoneTtlMs { tombstones[id] = at }
        }

        let items = mergeById(
            local: local.items, remote: remote.items,
            id: \.id, updatedAt: \.updatedAt, tombstones: tombstones
        ).sorted { $0.savedAt > $1.savedAt }

        let collections = mergeById(
            local: local.collections, remote: remote.collections,
            id: \.id, updatedAt: \.updatedAt, tombstones: tombstones
        ).sorted { $0.updatedAt < $1.updatedAt }

        // イベントは追記専用なので、(種別, 時刻) が同じものを同一とみなして和集合を取る
        var seenEvents = Set<UsageEvent>()
        let events = (local.events + remote.events)
            .filter { seenEvents.insert($0).inserted }
            .filter { now - $0.time <= eventTtlMs }
            .sorted { $0.time < $1.time }

        // Today's Pick は「日付が新しい方」の状態を採用。同じ日ならスキップ済みを合流させる
        let pickDate: String
        let pickSkipped: [String]
        if local.pickDate > remote.pickDate {
            (pickDate, pickSkipped) = (local.pickDate, local.pickSkippedIds)
        } else if local.pickDate < remote.pickDate {
            (pickDate, pickSkipped) = (remote.pickDate, remote.pickSkippedIds)
        } else {
            var seen = Set<String>()
            pickDate = local.pickDate
            pickSkipped = (local.pickSkippedIds + remote.pickSkippedIds).filter { seen.insert($0).inserted }
        }

        let itemIds = Set(items.map(\.id))
        return StashState(
            items: items,
            collections: collections,
            events: events,
            pickDate: pickDate,
            pickSkippedIds: pickSkipped.filter { itemIds.contains($0) },
            deletedIds: tombstones
        )
    }

    /// ID単位で新しい方を採用し、削除時刻より古いレコードは落とす。
    /// 「削除の後に別端末で編集した」場合は編集が勝つ（updatedAt > 削除時刻）ので復活する。
    private static func mergeById<T>(
        local: [T],
        remote: [T],
        id: KeyPath<T, String>,
        updatedAt: KeyPath<T, EpochMillis>,
        tombstones: [String: EpochMillis]
    ) -> [T] {
        // 挿入順を保つため、辞書とは別にキーの並びを持つ
        var order: [String] = []
        var merged: [String: T] = [:]
        for record in local + remote {
            let key = record[keyPath: id]
            guard let existing = merged[key] else {
                order.append(key)
                merged[key] = record
                continue
            }
            if record[keyPath: updatedAt] > existing[keyPath: updatedAt] {
                merged[key] = record
            }
        }
        return order.compactMap { key -> T? in
            guard let record = merged[key] else { return nil }
            guard let deletedAt = tombstones[key] else { return record }
            return record[keyPath: updatedAt] > deletedAt ? record : nil
        }
    }
}
