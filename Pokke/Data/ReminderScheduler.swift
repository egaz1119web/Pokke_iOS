import Foundation
import UserNotifications

/// リマインダーの端末通知への予約。
///
/// 保存内容（`StashItem.remindAt`）が正で、OSに登録済みの通知はその写し。
/// 個々の操作から「登録する／取り消す」を呼ぶ形にすると、クラウド同期で別端末から
/// 入ってきた変更や、まとめて削除したぶんを取りこぼす。そこで [sync] に
/// 保存内容ぜんぶを渡して差分を取る形にしてある（何度呼んでも結果は同じ）。
@MainActor
final class ReminderScheduler: ObservableObject {

    static let shared = ReminderScheduler()

    /// 通知の許可状態。入口の出し分けに使う
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// 予約済み通知の識別子。アイテム1件につき最大1つ
    private static func identifier(_ itemId: String) -> String { "reminder-\(itemId)" }

    /// 通知に載せる、押されたときに開くアイテムのID
    static let itemIdKey = "itemId"

    /// 通知の予約時刻。差分を取るために自分で持たせておく
    private static let fireAtKey = "fireAt"

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// 初回のリマインダー設定時に許可を求める。すでに答えが出ていれば聞き直さない
    @discardableResult
    func requestAuthorization() async -> Bool {
        await refreshAuthorization()
        switch authorization {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            // 一度断られたらOSはもう聞いてくれない。設定アプリへ案内する側の仕事
            return false
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await refreshAuthorization()
            return granted
        }
    }

    /// 保存内容に合わせて予約を揃える。
    ///
    /// 過去になったぶんは予約しない（もう鳴っている）。許可が無い間は
    /// 予約できないので何もしない — 許可が下りたときに呼び直せば追いつく。
    func sync(items: [StashItem]) async {
        await refreshAuthorization()
        let pending = await center.pendingNotificationRequests()
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        else {
            // 許可を取り消された後に予約だけ残っていても鳴らないが、
            // 保存内容と食い違ったまま残しておく理由も無いので片付ける
            if !pending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            }
            return
        }

        let now = nowMillis()
        let wanted = items.filter { ReminderPlan.isPending($0.remindAt, now: now) }
        let wantedIds = Set(wanted.map { Self.identifier($0.id) })

        let stale = pending.map(\.identifier).filter { !wantedIds.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        // 時刻が変わっていないものは触らない。取り消して入れ直すと、
        // 直前で入れ替わった瞬間に通知が落ちることがある
        var alreadyScheduled: [String: EpochMillis] = [:]
        for request in pending {
            if let at = request.content.userInfo[Self.fireAtKey] as? EpochMillis {
                alreadyScheduled[request.identifier] = at
            }
        }

        for item in wanted {
            guard let remindAt = item.remindAt else { continue }
            if alreadyScheduled[Self.identifier(item.id)] == remindAt { continue }
            schedule(item: item, at: remindAt)
        }
    }

    private func schedule(item: StashItem, at remindAt: EpochMillis) {
        let content = UNMutableNotificationContent()
        content.title = L.s("reminder_notification_title")
        content.body = item.title
        content.sound = .default
        content.userInfo = [Self.itemIdKey: item.id, Self.fireAtKey: remindAt]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(epochMillis: remindAt)
        )
        let request = UNNotificationRequest(
            identifier: Self.identifier(item.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        center.add(request) { error in
            if let error { print("[PokkeReminder] 予約に失敗した: \(error)") }
        }
    }
}

/// 通知が押されたときに、そのリンクの詳細を開くための受け渡し。
///
/// `UNUserNotificationCenterDelegate` はアプリ起動のかなり早い段階
/// （SwiftUIのViewが乗る前）に呼ばれることがあるので、IDをここに預けておき、
/// `RootView` が拾えるようになった時点で開く。
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationRouter()

    /// 開く先。拾った側が nil に戻す
    @Published var openItemId: String?

    /// アプリを開いている間に鳴ったぶんも、そのままバナーで見せる。
    /// 出さないと「設定したのに鳴らなかった」ように見える
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let itemId = response.notification.request.content.userInfo[ReminderScheduler.itemIdKey] as? String
        DispatchQueue.main.async { [weak self] in
            self?.openItemId = itemId
            completionHandler()
        }
    }
}
