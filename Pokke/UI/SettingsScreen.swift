import SwiftUI

struct SettingsScreen: View {
    let onShowGuide: () -> Void

    @ObservedObject private var auth = GoogleAuth.shared
    @ObservedObject private var consent = AdsConsent.shared
    @ObservedObject private var prefs = AppPrefs.shared

    @State private var loading = false
    @State private var message: String?

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

                SectionLabel(text: L.s("settings_reading"))
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                readingCard

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
    }

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
                        Text(profile.displayName ?? L.s("settings_google_account"))
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
                    Task { await signIn() }
                }
                .padding(.top, 12)
            }
        }
    }

    private var readingCard: some View {
        PokkeCard(padding: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.s("settings_open_in_app"))
                        .font(PokkeType.bodyLarge)
                        .foregroundStyle(Palette.ink)
                    Text(L.s("settings_open_in_app_description"))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                PokkeSwitch(
                    isOn: Binding(
                        get: { prefs.openInApp },
                        set: { prefs.setOpenInApp($0) }
                    ),
                    accessibilityLabel: L.s("settings_open_in_app")
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            CardDivider()
            SettingsLinkRow(
                icon: Lucide.bookOpen,
                text: L.s("settings_how_to_save"),
                action: onShowGuide
            )
        }
    }

    private func signIn() async {
        guard let rootViewController = GoogleAuth.rootViewController() else { return }
        loading = true
        message = nil
        switch await auth.signIn(presenting: rootViewController) {
        case .success:
            message = nil
        case .cancelled:
            break
        case let .failure(messageKey, detail):
            message = L.s(messageKey, detail ?? L.s("error_unknown"))
        }
        loading = false
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

/// カードの中の1行リンク。左にアイコン、右に矢印
private struct SettingsLinkRow: View {
    let icon: Lucide.Icon
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIconView(icon: icon, size: 17, color: Palette.accent700)
                Text(text)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.accent700)
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
