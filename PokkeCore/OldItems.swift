import Foundation

/// 「保存してからしばらく寝かせたままのリンク」の抽出。まとめて整理する画面で使う。
///
/// Foundation以外に依存しない純関数なので、通常のユニットテストで挙動を固定できる。
/// iOS固有の機能で、Android版には対応するファイルが無い。
enum OldItems {

    /// 「古い」とみなす経過日数
    static let thresholdDays = 7

    static let thresholdMs: EpochMillis = EpochMillis(thresholdDays) * 24 * 60 * 60 * 1000

    /// ホームに整理のお知らせを出す件数。
    /// 1件でも声をかけると、毎週使っている人には常にバナーが出ていることになる
    static let noticeThreshold = 10

    /// バナーを閉じてから、次に出すまでの猶予
    static let snoozeMs: EpochMillis = 7 * 24 * 60 * 60 * 1000

    /// 保存から `thresholdMs` 以上たったもの。古い順（いちばん長く寝かせたものが先頭）。
    ///
    /// アーカイブ済みも含める。保存件数の上限（`StashRepository.maxItems`）は
    /// アーカイブしても減らないので、そこを対象から外すと
    /// 「整理したのに空きが増えない」ことになってしまう。
    ///
    /// **お気に入りだけは外す**。ずっと残しておきたいという意思表示なので、
    /// 全選択から毎回チェックを外させるのではなく、はじめから並べない。
    /// 整理の画面に出さないことがそのまま「消えない」の保証になる
    static func stale(
        items: [StashItem],
        now: EpochMillis,
        thresholdMs: EpochMillis = thresholdMs
    ) -> [StashItem] {
        items
            .filter { !$0.favorite && now - $0.savedAt >= thresholdMs }
            .sorted { $0.savedAt < $1.savedAt }
    }

    /// ホームにお知らせを出すか。
    /// 十分たまっていること、直前に閉じられていないことの両方を見る
    static func showsNotice(
        staleCount: Int,
        snoozedAt: EpochMillis,
        now: EpochMillis
    ) -> Bool {
        staleCount >= noticeThreshold && now - snoozedAt >= snoozeMs
    }
}
