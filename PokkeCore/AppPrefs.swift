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
    }

    private let defaults = UserDefaults.standard

    @Published private(set) var viewMode: ViewMode = .list

    /// このアプリを最初に開いた時刻。レビュー依頼を「使い始めてどれくらいか」で測るために持つ
    private(set) var firstLaunchAt: EpochMillis = 0

    private init() {
        viewMode = defaults.string(forKey: Key.viewMode).flatMap(ViewMode.init(rawValue:)) ?? .list

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

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        defaults.set(mode.rawValue, forKey: Key.viewMode)
    }

    /// 端末ローカルの設定を初期状態へ戻す（[AppDataReset] から呼ぶ）
    func resetAll() {
        for key in [Key.onboarded, Key.viewMode, Key.firstLaunchAt, Key.reviewRequested] {
            defaults.removeObject(forKey: key)
        }
        viewMode = .list
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
