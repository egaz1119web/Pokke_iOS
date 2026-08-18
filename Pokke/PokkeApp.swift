import FirebaseCore
import FirebaseCrashlytics
import SwiftUI
import UserNotifications

@main
struct PokkeApp: App {

    init() {
        // GoogleService-Info.plist が無い状態で configure() すると落ちるので、
        // 置かれている時だけ初期化する。未設定なら設定画面に案内が出る（Android版と同じ挙動）
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
            // 開発中のクラッシュは自分で見えているので送らない。混ざると
            // 「配信版で何が起きているか」が読めなくなる（Android版と同じ切り分け）
            #if DEBUG
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            #else
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            #endif
        }
        StashRepository.shared.initialize()
        AuthService.shared.restoreSession()
        // 通知の受け取り口は起動が終わる前に差しておく必要がある。
        // 遅れると、通知から起動したときの1回目を取りこぼす
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // 同意（EEA/英国で必須）が取れてから広告SDKを初期化する。
                    // 画面が乗ってからでないとフォームを出せないので init ではなくここで呼ぶ
                    AdsConsent.shared.gather()
                    // 共有拡張が保存した分や、保存時に取れなかったサムネイル・本文を埋め直す
                    StashRepository.shared.retryMissingMetadata()
                }
                // Googleログインのコールバック（REVERSED_CLIENT_ID のカスタムURLスキーム）
                .onOpenURL { url in
                    AuthService.shared.handle(url: url)
                }
        }
    }
}
