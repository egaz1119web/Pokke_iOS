import Foundation

/// 星評価ダイアログを出す頃合いの判定。
///
/// ダイアログ自体は Apple 純正のものに任せる（表示回数は OS が年3回までに絞る）。
/// こちらの役目は「頼んでよい相手か」を決めることだけ。
///
/// 条件は「保存が貯まっている」かつ「使い始めてから日が経っている」の両方。
/// 件数だけだと、入れてすぐ大量に流し込んだ人にも初日に出てしまい、
/// 日数だけだと、入れたきり使っていない人に出てしまう。
enum ReviewPrompt {

    /// これだけ保存していれば、アプリの用途は果たせていると見なす
    static let requiredItemCount = 10

    /// 初回起動からこの日数が経つまでは声をかけない
    static let requiredDays = 3

    /// - Parameters:
    ///   - itemCount: 保存済みリンクの件数（アーカイブ済みも含む）
    ///   - firstLaunchAt: 初回起動の時刻
    ///   - alreadyRequested: すでに一度依頼したか
    ///   - now: 現在時刻
    static func shouldRequest(
        itemCount: Int,
        firstLaunchAt: EpochMillis,
        alreadyRequested: Bool,
        now: EpochMillis = nowMillis()
    ) -> Bool {
        guard !alreadyRequested else { return false }
        guard itemCount >= requiredItemCount else { return false }

        // 端末の時計が巻き戻ると経過日数が負になりうる。その場合は条件未達として扱う
        let elapsedDays = (now - firstLaunchAt) / (24 * 60 * 60 * 1000)
        return elapsedDays >= Int64(requiredDays)
    }
}
