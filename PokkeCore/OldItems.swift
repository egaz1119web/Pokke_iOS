import Foundation

/// 「保存してからしばらく寝かせたままのリンク」の抽出。まとめて整理する画面で使う。
///
/// Foundation以外に依存しない純関数なので、通常のユニットテストで挙動を固定できる。
/// Android版の `data/OldItems.kt` と同じ内容（しきい値も揃えてある）。
enum OldItems {

    private static let dayMs: EpochMillis = 24 * 60 * 60 * 1000

    /// 「古い」とみなす経過日数
    static let thresholdDays = 7

    static let thresholdMs: EpochMillis = EpochMillis(thresholdDays) * dayMs

    /// ホームから声をかける対象の経過日数。整理シートに並べる `thresholdDays` より長い。
    ///
    /// 並べる基準と促す基準を同じにすると、毎週きちんと保存している人ほど
    /// 常に条件を満たしてしまう。「入れて1週間たった」は片付けの候補ではあっても、
    /// 手を止めさせてまで知らせることではない
    static let noticeDays = 30

    static let noticeMs: EpochMillis = EpochMillis(noticeDays) * dayMs

    /// 声をかけるのに最低限必要な件数。
    ///
    /// 保存の上限は300件（`StashRepository.maxItems`）なので、
    /// 10件やそこらの滞留は整理するほどの量ではない
    static let noticeMinCount = 30

    /// 保存件数のうち、これだけの割合が滞留していたら声をかける。
    /// 少数しか持っていない人に絶対数だけで迫らないよう、`noticeMinCount` と併用する
    static let noticeRatioDenominator = 3

    /// 閉じられるたびに延びる猶予。最後まで使い切ったら二度と出さない。
    ///
    /// 固定の猶予だと、閉じても同じ間隔で戻ってくる。
    /// 「今は要らない」を繰り返した人には、そもそも要らない機能だとみなす
    static let snoozeStepsMs: [EpochMillis] = [30 * dayMs, 90 * dayMs]

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

    /// 声をかける根拠になる件数。`stale` とは対象が違う。
    ///
    /// アーカイブ済みを数に入れない。読み終えて片付けたものは、本人の中では
    /// 済んだ話になっている。それを「寝かせたまま」として数えると、
    /// きちんと消化している人ほど件数が膨らんで急かされることになる
    /// （消せば枠が空くのは事実なので、シートには `stale` のとおり並べる）
    static func noticeCount(items: [StashItem], now: EpochMillis) -> Int {
        items.filter { !$0.archived && !$0.favorite && now - $0.savedAt >= noticeMs }.count
    }

    /// 声をかけ始める件数。持っている量に応じて動かす。
    ///
    /// 固定値だと、上限いっぱいまで貯めて使う人には低すぎ、
    /// 数十件で回している人には高すぎる
    static func noticeThreshold(totalCount: Int) -> Int {
        max(noticeMinCount, totalCount / noticeRatioDenominator)
    }

    /// 次に出すまでの猶予。nil は「もう出さない」。
    ///
    /// `dismissCount` は通算で閉じた回数。一度も閉じていなければ猶予なし
    static func snoozeMs(dismissCount: Int) -> EpochMillis? {
        guard dismissCount > 0 else { return 0 }
        guard dismissCount <= snoozeStepsMs.count else { return nil }
        return snoozeStepsMs[dismissCount - 1]
    }

    /// ホームにお知らせを出すか。
    /// 十分たまっていること、閉じてからの猶予が明けていることの両方を見る
    static func showsNotice(
        staleCount: Int,
        totalCount: Int,
        snoozedAt: EpochMillis,
        dismissCount: Int,
        now: EpochMillis
    ) -> Bool {
        guard staleCount >= noticeThreshold(totalCount: totalCount) else { return false }
        guard let snooze = snoozeMs(dismissCount: dismissCount) else { return false }
        return now - snoozedAt >= snooze
    }
}
