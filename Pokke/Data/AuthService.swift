import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn
import UIKit

enum AuthProviderKind: Equatable {
    case google
    case apple
}

/// ログインで得たプロフィール（uidはFirebase同期のキーとして使う）
struct AuthProfile: Equatable {
    var uid: String
    var displayName: String?
    var email: String
    var photoUrl: String?
    /// どちらでサインインしたか。名前が無いときのフォールバック表示に使う
    var provider: AuthProviderKind?
}

enum SignInResult {
    case success(AuthProfile)
    case cancelled
    /// 表示文言はUI層で解決する。detail は %1$@ に差し込む補足
    case failure(messageKey: String, detail: String?)
}

/// Google / Apple のログイン ＋ Firebase Authへのサインイン。
///
/// App Store ガイドライン4.8「サードパーティログインを使うなら同等のログインも用意する」に
/// 応えるため、Googleに加えて Sign in with Apple を用意している
/// （AndroidにはGoogleログインしか無いので、この点はiOS固有）。
/// どちらでサインインしても行き着く先は同じ Firebase Auth の uid で、
/// Firestoreの同期キーもUIの「サインイン中」判定もこの1つの `profile` を見る。
///
/// Android版は GoogleSignInClient のIntentを使うが、iOSでは GoogleSignIn-iOS SDK が
/// SFAuthenticationSession を出すので、呼び出し元は presenting する
/// UIViewController を渡すだけでよい。
@MainActor
final class AuthService: ObservableObject {

    static let shared = AuthService()

    @Published private(set) var profile: AuthProfile?

    private var authListener: AuthStateDidChangeListenerHandle?

    /// Sign in with Apple の直前に発行したnonce（生値）。
    /// リプレイ攻撃対策としてAppleにはこれのSHA256だけを渡し、
    /// Firebase側の検証には生値を渡す
    private var currentAppleNonce: String?

    private init() {}

    /// GoogleService-Info.plist 配置 & Googleプロバイダのクライアント IDが揃っているか
    var isConfigured: Bool { FirebaseApp.app()?.options.clientID != nil }

    private func toProfile(_ user: User) -> AuthProfile {
        let provider: AuthProviderKind? = switch user.providerData.first?.providerID {
        case GoogleAuthProvider.id: .google
        case "apple.com": .apple
        default: nil
        }
        return AuthProfile(
            uid: user.uid,
            displayName: user.displayName,
            email: user.email ?? "",
            photoUrl: user.photoURL?.absoluteString,
            provider: provider
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
            MainActor.assumeIsolated { AuthService.shared.apply(user: user) }
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
    func signInWithGoogle(presenting: UIViewController) async -> SignInResult {
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
            return await signIn(with: credential)
        } catch let error as NSError {
            if error.domain == kGIDSignInErrorDomain, error.code == GIDSignInError.canceled.rawValue {
                // ユーザーが自分で閉じた。エラー表示はしない
                return .cancelled
            }
            return .failure(messageKey: "sign_in_error_generic", detail: error.localizedDescription)
        }
    }

    /// `SignInWithAppleButton` の `onRequest` から呼ぶ。返した値をnonceにそのままセットしてもらう
    func appleSignInRequest() -> String {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        return Self.sha256(nonce)
    }

    /// `SignInWithAppleButton` の `onCompletion` が成功を返したら呼ぶ
    func signInWithApple(authorization: ASAuthorization) async -> SignInResult {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return .failure(messageKey: "sign_in_error_no_id_token", detail: nil)
        }
        // nonceは1回のリクエストにつき1つ。無い＝ appleSignInRequest() を経ていないので信用しない
        guard let nonce = currentAppleNonce else {
            return .failure(messageKey: "sign_in_error_no_id_token", detail: nil)
        }
        currentAppleNonce = nil
        guard let tokenData = appleCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            return .failure(messageKey: "sign_in_error_no_id_token", detail: nil)
        }
        // fullNameはAppleが初回サインイン時にしか返さない。Firebase側がユーザーの
        // displayNameとして保存し、2回目以降のサインインでもFirebase側の値が残る
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
        return await signIn(with: credential)
    }

    private func signIn(with credential: AuthCredential) async -> SignInResult {
        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            let profile = toProfile(authResult.user)
            self.profile = profile
            FirestoreSync.shared.start(uid: authResult.user.uid)
            return .success(profile)
        } catch let error as NSError {
            if error.domain == AuthErrorDomain {
                // 認可までは通ったが、Firebase側で弾かれた
                // （Console で対象プロバイダが無効、Bundle IDの不一致など）
                return .failure(messageKey: "sign_in_error_firebase", detail: nil)
            }
            return .failure(messageKey: "sign_in_error_generic", detail: error.localizedDescription)
        }
    }

    /// サインアウトして同期を止める
    func signOut() {
        FirestoreSync.shared.stop()
        // Appleでサインインしていた場合は無害な空振りになるだけ
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

    // ---- Sign in with Apple のnonce生成（Firebase公式サンプルと同じ手順） ----

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var randoms: [UInt8] = []
            randoms.reserveCapacity(16)
            for _ in 0..<16 {
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                precondition(status == errSecSuccess, "nonceの生成に失敗しました")
                randoms.append(random)
            }
            for random in randoms where remainingLength > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
