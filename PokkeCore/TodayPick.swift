import Foundation

/// Today's Pick（1日1件の再訪候補）の選定ロジック。純関数で単体テスト対象。
enum TodayPick {

    /// 未読（未アーカイブ・未オープン）のうち、今日まだスキップされていない
    /// 最も古いアイテムを返す。候補がなければnil。
    static func choose(items: [StashItem], skippedIds: [String]) -> StashItem? {
        let skipped = Set(skippedIds)
        return items
            .filter { $0.unread && !skipped.contains($0.id) }
            .min { $0.savedAt < $1.savedAt }
    }
}
