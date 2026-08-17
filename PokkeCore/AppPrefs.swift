import Combine
import Foundation

/// ホーム一覧の表示形式
enum ViewMode: String {
    case list = "LIST"
    case grid = "GRID"
}

/// 端末ローカルの設定。
///
/// 表示形式や初回案内の既読は「その端末での見え方」なので、
/// クラウド同期する `StashState` ではなく UserDefaults に置く
/// （Android版の SharedPreferences と同じ扱い）。
@MainActor
final class AppPrefs: ObservableObject {

    static let shared = AppPrefs()

    private enum Key {
        static let onboarded = "onboarded"
        static let viewMode = "view_mode"
        static let firstLaunchAt = "first_launch_at"
        static let reviewRequested = "review_requested"
        static let cleanupSnoozedAt = "cleanup_snoozed_at"
        static let cleanupDismissCount = "cleanup_dismiss_count"
        static let cleanupNotice = "cleanup_notice"
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var viewMode: ViewMode = .list

    /// 古いリンクの整理をすすめるバナーを最後に閉じた時刻。
    /// 閉じたことは端末ごとの都合なので、同期する `StashState` には入れない
    @Published private(set) var cleanupSnoozedAt: EpochMillis = 0

    /// 整理のバナーを通算で閉じた回数。次の猶予を決めるのに使う（`OldItems.snoozeMs`）。
    /// 閉じた回数が猶予に効くので、閉じた時刻と同じく端末ごとに持つ
    @Published private(set) var cleanupDismissCount: Int = 0

    /// 整理のバナーを出してよいか。設定から切れる。
    ///
    /// 猶予（`cleanupSnoozedAt`）とは別に持つ。「今は要らない」と
    /// 「二度と出すな」は別の意思表示で、後者を延期として扱うと必ず戻ってきてしまう
    @Published private(set) var cleanupNoticeEnabled = true

    /// このアプリを最初に開いた時刻。レビュー依頼を「使い始めてどれくらいか」で測るために持つ
    private(set) var firstLaunchAt: EpochMillis = 0

    private init() {
        viewMode = defaults.string(forKey: Key.viewMode).flatMap(ViewMode.init(rawValue:)) ?? .list
        cleanupSnoozedAt = (defaults.object(forKey: Key.cleanupSnoozedAt) as? Int64) ?? 0
        cleanupNoticeEnabled = (defaults.object(forKey: Key.cleanupNotice) as? Bool) ?? true
        // 回数を数え始める前から使っている人の扱い。閉じた時刻だけが残っていたら
        // 1回ぶんとみなす。0のままだと猶予なしになり、閉じた直後にまた出てしまう
        cleanupDismissCount = (defaults.object(forKey: Key.cleanupDismissCount) as? Int)
            ?? (cleanupSnoozedAt > 0 ? 1 : 0)

        // 記録が無い＝今回が初回。以後この値は動かさない
        if let stored = defaults.object(forKey: Key.firstLaunchAt) as? Int64, stored > 0 {
            firstLaunchAt = stored
        } else {
            firstLaunchAt = nowMillis()
            defaults.set(firstLaunchAt, forKey: Key.firstLaunchAt)
        }
    }

    /// 初回案内を出すべきか（まだ一度も見せていない）
    var needsOnboarding: Bool { !defaults.bool(forKey: Key.onboarded) }

    func markOnboarded() {
        defaults.set(true, forKey: Key.onboarded)
    }

    /// レビュー依頼をもう投げたか。OS側も回数を絞るが、こちらでも一度きりにする
    var reviewRequested: Bool { defaults.bool(forKey: Key.reviewRequested) }

    func markReviewRequested() {
        defaults.set(true, forKey: Key.reviewRequested)
    }

    /// 整理のお知らせを閉じた。次に出るのは `OldItems.snoozeMs` のあと。
    /// 閉じるたびに猶予が延び、使い切ると出なくなる
    func snoozeCleanupNotice() {
        cleanupSnoozedAt = nowMillis()
        cleanupDismissCount += 1
        defaults.set(cleanupSnoozedAt, forKey: Key.cleanupSnoozedAt)
        defaults.set(cleanupDismissCount, forKey: Key.cleanupDismissCount)
    }

    /// 整理のお知らせの入切。
    ///
    /// 入れ直したときは閉じた記録も戻す。延期の履歴を持ち越すと、
    /// 自分で入れ直したのに何ヶ月も出てこないことになる
    func setCleanupNoticeEnabled(_ enabled: Bool) {
        cleanupNoticeEnabled = enabled
        defaults.set(enabled, forKey: Key.cleanupNotice)
        guard enabled else { return }
        cleanupSnoozedAt = 0
        cleanupDismissCount = 0
        defaults.set(EpochMillis(0), forKey: Key.cleanupSnoozedAt)
        defaults.set(0, forKey: Key.cleanupDismissCount)
    }

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        defaults.set(mode.rawValue, forKey: Key.viewMode)
    }

    /// 端末ローカルの設定を初期状態へ戻す（[AppDataReset] から呼ぶ）
    func resetAll() {
        for key in [
            Key.onboarded, Key.viewMode, Key.firstLaunchAt, Key.reviewRequested,
            Key.cleanupSnoozedAt, Key.cleanupDismissCount, Key.cleanupNotice,
        ] {
            defaults.removeObject(forKey: key)
        }
        viewMode = .list
        cleanupSnoozedAt = 0
        cleanupDismissCount = 0
        cleanupNoticeEnabled = true
        // 消したままだと0になり「使い始めてどれくらいか」の判定が壊れるので入れ直す
        firstLaunchAt = nowMillis()
        defaults.set(firstLaunchAt, forKey: Key.firstLaunchAt)
    }
}

/// 端末に残っているアプリのデータを消す口。
///
/// 保存した内容（stash.json）と端末ローカルの設定（UserDefaults）は別々に持っているので、
/// 消し忘れが出ないよう1か所にまとめている。アカウント（Firebase Auth）とクラウドの
/// 内容には触らない — そちらは `AuthService.deleteAccount` の担当。
@MainActor
enum AppDataReset {
    static func eraseLocal() {
        StashRepository.shared.deleteEverything()
        AppPrefs.shared.resetAll()
    }
}
