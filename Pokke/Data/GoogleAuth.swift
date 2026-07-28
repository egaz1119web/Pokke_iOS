import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import UIKit

/// Googleログインで得たプロフィール（uidはFirebase同期のキーとして使う）
struct GoogleProfile: Equatable {
    var uid: String
    var displayName: String?
    var email: String
    var photoUrl: String?
}

enum SignInResult {
    case success(GoogleProfile)
    case cancelled
    /// 表示文言はUI層で解決する。detail は %1$@ に差し込む補足
    case failure(messageKey: String, detail: String?)
}

/// Googleログイン + Firebase Authへのサインイン。
///
/// Android版は GoogleSignInClient のIntentを使うが、iOSでは GoogleSignIn-iOS SDK が
/// SFAuthenticationSession を出すので、呼び出し元は presenting する
/// UIViewController を渡すだけでよい。
@MainActor
final class GoogleAuth: ObservableObject {

    static let shared = GoogleAuth()

    @Published private(set) var profile: GoogleProfile?

    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {}

    /// GoogleService-Info.plist 配置 & GoogleプロバイダのクライアントIDが揃っているか
    var isConfigured: Bool { FirebaseApp.app()?.options.clientID != nil }

    private func toProfile(_ user: User) -> GoogleProfile {
        GoogleProfile(
            uid: user.uid,
            displayName: user.displayName,
            email: user.email ?? "",
            photoUrl: user.photoURL?.absoluteString
        )
    }

    /// アプリ起動時に呼ぶ。既にFirebaseにサインイン済みならプロフィールを復元して同期を再開する。
    ///
    /// `Auth.auth().currentUser` を起動直後に一度読むだけだと、キーチェーンからの復元が
    /// 間に合わずサインイン済みなのに未ログイン扱いになることがある。状態変化を購読して、
    /// トークン失効でサインアウトされた場合にも追従できるようにしている。
    func restoreSession() {
        guard isConfigured, authListener == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { _, user in
            // Firebase はこのコールバックをメインスレッドで呼ぶ
            MainActor.assumeIsolated { GoogleAuth.shared.apply(user: user) }
        }
    }

    private func apply(user: User?) {
        guard let user else {
            profile = nil
            FirestoreSync.shared.stop()
            return
        }
        profile = toProfile(user)
        // start は同じuidなら何もしないので、状態変化のたびに呼んでも安全
        FirestoreSync.shared.start(uid: user.uid)
    }

    /// Googleログイン画面を出し、Firebase Authへ接続して同期を開始する
    func signIn(presenting: UIViewController) async -> SignInResult {
        guard let clientId = FirebaseApp.app()?.options.clientID else {
            return .failure(messageKey: "sign_in_error_no_id_token", detail: nil)
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
            guard let idToken = result.user.idToken?.tokenString else {
                return .failure(messageKey: "sign_in_error_no_id_token", detail: nil)
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            let profile = toProfile(authResult.user)
            self.profile = profile
            FirestoreSync.shared.start(uid: authResult.user.uid)
            return .success(profile)
        } catch let error as NSError {
            switch error.domain {
            case kGIDSignInErrorDomain where error.code == GIDSignInError.canceled.rawValue:
                // ユーザーが自分で閉じた。エラー表示はしない
                return .cancelled
            case AuthErrorDomain:
                // Googleの認可までは通ったが、Firebase側で弾かれた
                // （Console で Google プロバイダが無効、Bundle IDの不一致など）
                return .failure(messageKey: "sign_in_error_firebase", detail: nil)
            default:
                return .failure(messageKey: "sign_in_error_generic", detail: error.localizedDescription)
            }
        }
    }

    /// サインアウトして同期を止める
    func signOut() {
        FirestoreSync.shared.stop()
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        profile = nil
    }

    /// Googleログインのコールバック（REVERSED_CLIENT_ID のカスタムURLスキーム）
    @discardableResult
    func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// 画面を出すためのルートViewController
    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
