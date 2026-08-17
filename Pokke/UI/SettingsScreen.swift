import AuthenticationServices
import SwiftUI

struct SettingsScreen: View {
    let onShowGuide: () -> Void
    let onCleanup: () -> Void

    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var consent = AdsConsent.shared
    @ObservedObject private var prefs = AppPrefs.shared
    @EnvironmentObject private var toast: ToastController

    /// 整理のお知らせの入切。切ったときは猶予をそのまま残し、
    /// 入れ直したときだけ閉じた記録を戻す（`AppPrefs.setCleanupNoticeEnabled`）
    private var cleanupNoticeBinding: Binding<Bool> {
        Binding(
            get: { prefs.cleanupNoticeEnabled },
            set: { prefs.setCleanupNoticeEnabled($0) }
        )
    }

    @State private var loading = false
    @State private var message: String?
    @State private var showDeleteConfirm = false
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: L.s("settings_title"))

                SectionLabel(text: L.s("settings_account"))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                accountCard

                SectionLabel(text: L.s("settings_cloud_sync"))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                // ログインしていなくても出す。隠してしまうと同期という機能自体に気付けない
                SyncCard(signedIn: auth.profile != nil)

                SectionLabel(text: L.s("settings_guide"))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                guideCard

                // 同意が必要な地域（EEA/英国）でのみ表示。あとから変更できる導線はUMPの要件
                if consent.isPrivacyOptionsRequired {
                    SectionLabel(text: L.s("settings_ads"))
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                    PokkeCard(padding: 0) {
                        SettingsLinkRow(icon: Lucide.settings, text: L.s("settings_ad_privacy")) {
                            consent.showPrivacyOptionsForm()
                        }
                    }
                }

                SectionLabel(text: L.s("settings_data"))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                // 整理はホームのバナーからも入れるが、閉じた後・件数が少ないうちは
                // 出ないので、いつでも辿れる場所をここに用意しておく
                PokkeCard(padding: 0) {
                    SettingsLinkRow(icon: Lucide.clock, text: L.s("settings_cleanup"), action: onCleanup)
                    CardDivider()
                    // 上の導線と対にして置く。声をかけるのを止めても、整理そのものは
                    // いつでもできることが同じカードの中で分かる
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L.s("settings_cleanup_notice"))
                                .font(PokkeType.bodyLarge)
                                .foregroundStyle(Palette.ink)
                            Text(L.s("settings_cleanup_notice_description", OldItems.noticeDays))
                                .font(PokkeType.bodySmall)
                                .foregroundStyle(Palette.neutral600)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        PokkeSwitch(
                            isOn: cleanupNoticeBinding,
                            accessibilityLabel: L.s("settings_cleanup_notice")
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .padding(.bottom, 10)
                deleteCard

                if !auth.isConfigured {
                    Text(L.s("settings_firebase_not_configured"))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                if let message {
                    Text(message)
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                Text("Pokke \(appVersion)")
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral500)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
            }
            .padding(.horizontal, screenPadding)
            .padding(.top, 18)
            .padding(.bottom, bottomContentPadding)
        }
        .scrollIndicators(.hidden)
        // 押し間違いを防ぐ確認。何が消えるのかを先に全部書いておく
        .alert(
            L.s(signedIn ? "delete_account_title" : "delete_local_title"),
            isPresented: $showDeleteConfirm
        ) {
            Button(L.s("action_cancel"), role: .cancel) {}
            Button(L.s("action_delete"), role: .destructive) {
                Task { await deleteData() }
            }
        } message: {
            Text(L.s(signedIn ? "delete_account_message" : "delete_local_message"))
        }
    }

    private var signedIn: Bool { auth.profile != nil }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    @ViewBuilder
    private var accountCard: some View {
        PokkeCard(padding: 16) {
            if let profile = auth.profile {
                HStack(spacing: 12) {
                    if let photoUrl = profile.photoUrl, let url = URL(string: photoUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Palette.neutral200
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(profile.displayName ?? fallbackAccountName(for: profile.provider))
                            .font(PokkeType.bodyLarge)
                            .foregroundStyle(Palette.ink)
                        Text(profile.email)
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(Palette.neutral600)
                    }
                    Spacer(minLength: 0)
                }
                SettingsPillButton(title: L.s("settings_sign_out")) {
                    auth.signOut()
                    message = nil
                }
                .padding(.top, 12)
            } else {
                Text(L.s("settings_sign_in_description"))
                    .font(PokkeType.bodyMedium)
                    .lineSpacing(PokkeType.bodyLineSpacing)
                    .foregroundStyle(Palette.neutral800)
                    .fixedSize(horizontal: false, vertical: true)
                // ブランドガイドラインどおり、白地に4色ロゴ＋濃色の文字
                GoogleSignInButton(enabled: !loading && auth.isConfigured, loading: loading) {
                    Task { await signInWithGoogle() }
                }
                .padding(.top, 12)
                // Googleだけだと審査ガイドライン4.8（サードパーティログインを使うなら
                // 同等のログインも用意する）に抵触するため、Sign in with Appleも並べる
                AppleSignInButton(enabled: !loading && auth.isConfigured, loading: loading) { result in
                    Task { await signInWithApple(result) }
                }
                .padding(.top, 10)
            }
        }
    }

    /// アカウントとデータの削除。
    ///
    /// ログイン中はアカウントごと消す（審査ガイドライン5.1.1(v)の要件で、アプリの中だけで
    /// 完了できる必要がある）。未ログインでも端末に残る保存内容は消せるようにしておく。
    @ViewBuilder
    private var deleteCard: some View {
        PokkeCard(padding: 0) {
            if deleting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Palette.danger)
                    Text(L.s("delete_account_deleting"))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.danger)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else {
                SettingsLinkRow(
                    icon: Lucide.trash,
                    text: L.s(signedIn ? "settings_delete_account" : "settings_delete_local"),
                    tint: Palette.danger
                ) {
                    showDeleteConfirm = true
                }
            }
        }
        Text(L.s(signedIn ? "settings_delete_account_note" : "settings_delete_local_note"))
            .font(PokkeType.bodySmall)
            .foregroundStyle(Palette.neutral600)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    private var guideCard: some View {
        PokkeCard(padding: 0) {
            SettingsLinkRow(
                icon: Lucide.bookOpen,
                text: L.s("settings_how_to_save"),
                action: onShowGuide
            )
        }
    }

    private func fallbackAccountName(for provider: AuthProviderKind?) -> String {
        L.s(provider == .apple ? "settings_apple_account" : "settings_google_account")
    }

    private func signInWithGoogle() async {
        guard let rootViewController = AuthService.rootViewController() else { return }
        loading = true
        message = nil
        apply(await auth.signInWithGoogle(presenting: rootViewController))
        loading = false
    }

    private func signInWithApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .success(authorization):
            loading = true
            message = nil
            apply(await auth.signInWithApple(authorization: authorization))
            loading = false
        case let .failure(error):
            // ユーザーが自分でシートを閉じた場合はGoogleのキャンセル同様、エラー表示はしない
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            message = L.s("sign_in_error_generic", error.localizedDescription)
        }
    }

    private func deleteData() async {
        let wasSignedIn = signedIn
        deleting = true
        message = nil
        let result: DeleteAccountResult
        if wasSignedIn, let rootViewController = AuthService.rootViewController() {
            result = await auth.deleteAccount(presenting: rootViewController)
        } else {
            AppDataReset.eraseLocal()
            result = .success
        }
        deleting = false
        switch result {
        case .success:
            toast.show(L.s(wasSignedIn ? "delete_account_done" : "delete_local_done"))
        case .cancelled:
            // 本人確認のログイン画面を自分で閉じた。何も消していない
            break
        case let .failure(messageKey, detail):
            message = L.s(messageKey, detail ?? L.s("error_unknown"))
        }
    }

    private func apply(_ result: SignInResult) {
        switch result {
        case .success, .cancelled:
            message = nil
        case let .failure(messageKey, detail):
            message = L.s(messageKey, detail ?? L.s("error_unknown"))
        }
    }
}

/// 白地・細枠のGoogleログインボタン
private struct GoogleSignInButton: View {
    let enabled: Bool
    let loading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if loading {
                    ProgressView().controlSize(.small).tint(Palette.accent)
                } else {
                    GoogleLogo(size: 18)
                    Text(L.s("settings_sign_in"))
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(enabled ? Palette.ink : Palette.neutral500)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.98))
        .disabled(!enabled)
    }
}

/// Sign in with Apple ボタン。
///
/// SwiftUIの `SignInWithAppleButton` は見た目こそHIG準拠だが、ラベルの文字が
/// システムフォント（SF Pro）固定でアプリの書体（Figtree/Zen Maru Gothic）と
/// 揃わず浮いて見える。HIGは公式ロゴマークさえ改変せずそのまま使えば自前ボタンを
/// 作ってよいとしているので、Googleボタンと全く同じ見た目・書体で組み直している。
private struct AppleSignInButton: View {
    let enabled: Bool
    let loading: Bool
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        Button(action: start) {
            HStack(spacing: 10) {
                if loading {
                    ProgressView().controlSize(.small).tint(Palette.accent)
                } else {
                    // "apple.logo" がAppleの公式ロゴマーク（SF Symbols）。改変せず使う
                    Image(systemName: "apple.logo")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(enabled ? Palette.ink : Palette.neutral500)
                    Text(L.s("settings_sign_in_apple"))
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(enabled ? Palette.ink : Palette.neutral500)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.98))
        .disabled(!enabled)
    }

    private func start() {
        // 画面の出し方と委譲先の保持は AuthService 側にまとめてある
        // （アカウント削除時の本人確認でも同じ道を通るため）
        Task { onCompletion(await AuthService.shared.requestAppleAuthorization()) }
    }
}

/// カードの中の1行リンク。左にアイコン、右に矢印
private struct SettingsLinkRow: View {
    let icon: Lucide.Icon
    let text: String
    /// 削除のような取り消せない操作だけ色を変える
    var tint: Color = Palette.accent700
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIconView(icon: icon, size: 17, color: tint)
                Text(text)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                LucideIconView(icon: Lucide.chevronRight, size: 16, color: Palette.neutral400)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// カードの中に置く、控えめなピルボタン
private struct SettingsPillButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PokkeType.labelMedium)
                .foregroundStyle(enabled ? Palette.ink : Palette.neutral500)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.98))
        .disabled(!enabled)
    }
}

/// 同期の現在地（接続中／送信中／完了／エラー）と手動同期ボタン。
///
/// 未ログインでもカードごと出す。ログイン中しか出さないと、
/// そもそも同期できることに気付けないため。ただし送る先が無いので操作はできない。
private struct SyncCard: View {
    let signedIn: Bool

    @ObservedObject private var sync = FirestoreSync.shared
    @ObservedObject private var repository = StashRepository.shared

    var body: some View {
        PokkeCard(padding: 16) {
            HStack(spacing: 10) {
                switch sync.status {
                case .syncing, .connecting:
                    ProgressView().controlSize(.small).tint(Palette.accent)
                default:
                    LucideIconView(icon: statusIcon, size: 16, color: statusColor)
                }
                Text(statusLabel)
                    .font(PokkeType.bodyMedium)
                    .foregroundStyle(isError ? Palette.danger : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Text(L.s(
                signedIn ? "sync_stats" : "sync_needs_sign_in",
                repository.state.items.count,
                repository.state.collections.count
            ))
            .font(PokkeType.bodySmall)
            .foregroundStyle(Palette.neutral600)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)

            SettingsPillButton(
                title: L.s("settings_sync_now"),
                enabled: signedIn && sync.status != .syncing
            ) {
                sync.syncNow()
            }
            .padding(.top, 12)
        }
    }

    private var isError: Bool {
        if case .failure = sync.status { return true }
        return false
    }

    private var statusIcon: Lucide.Icon {
        switch sync.status {
        case .synced: return Lucide.circleCheck
        case .failure: return Lucide.triangleAlert
        case .pending: return Lucide.clock
        default: return Lucide.cloud
        }
    }

    private var statusColor: Color {
        switch sync.status {
        case .synced: return Palette.accent2_600
        case .failure: return Palette.danger
        default: return Palette.neutral600
        }
    }

    private var statusLabel: String {
        switch sync.status {
        case .off: return L.s("sync_status_off")
        case .connecting: return L.s("sync_status_connecting")
        case .syncing: return L.s("sync_status_syncing")
        case .pending: return L.s("sync_status_pending")
        case let .synced(at): return L.s("sync_status_synced", relativeTime(at))
        case let .failure(messageKey, detail):
            // detail を持たない文言でも余分な引数は無視されるため、まとめて解決できる
            return L.s(messageKey, detail ?? L.s("error_unknown"))
        }
    }
}
