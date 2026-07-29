import FirebaseCore
import SwiftUI

@main
struct PokkeApp: App {

    init() {
        // GoogleService-Info.plist が無い状態で configure() すると落ちるので、
        // 置かれている時だけ初期化する。未設定なら設定画面に案内が出る（Android版と同じ挙動）
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        }
        StashRepository.shared.initialize()
        AuthService.shared.restoreSession()
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
