import SwiftUI

struct SettingsScreen: View {
    @ObservedObject private var auth = GoogleAuth.shared
    @ObservedObject private var consent = AdsConsent.shared

    @State private var loading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L.s("settings_title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.onSurface)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Text(L.s("settings_account")).font(.subheadline.weight(.medium))
                    .padding(.bottom, 8)
                accountCard

                if auth.profile != nil {
                    Text(L.s("settings_cloud_sync")).font(.subheadline.weight(.medium))
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    SyncCard()
                }

                // 同意が必要な地域（EEA/英国）でのみ表示。あとから変更できる導線はUMPの要件
                if consent.isPrivacyOptionsRequired {
                    Text(L.s("settings_ads")).font(.subheadline.weight(.medium))
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    Button(L.s("settings_ad_privacy")) {
                        consent.showPrivacyOptionsForm()
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.primary)
                    .frame(maxWidth: .infinity)
                }

                if !auth.isConfigured {
                    Text(L.s("settings_firebase_not_configured"))
                        .font(.caption)
                        .foregroundStyle(Palette.error)
                        .padding(.top, 12)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Palette.error)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.appBackground)
    }

    @ViewBuilder
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let profile = auth.profile {
                HStack(spacing: 12) {
                    if let photoUrl = profile.photoUrl, let url = URL(string: photoUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Palette.placeholderBg
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName ?? L.s("settings_google_account"))
                            .font(.headline)
                            .foregroundStyle(Palette.onSurface)
                        Text(profile.email)
                            .font(.caption)
                            .foregroundStyle(Palette.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                }
                Button(L.s("settings_sign_out")) {
                    auth.signOut()
                    message = nil
                }
                .buttonStyle(.bordered)
                .tint(Palette.primary)
                .frame(maxWidth: .infinity)
            } else {
                Text(L.s("settings_sign_in_description"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
                Button {
                    Task { await signIn() }
                } label: {
                    if loading {
                        ProgressView().tint(Palette.onPrimary)
                    } else {
                        Text(L.s("settings_sign_in"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.primary)
                .frame(maxWidth: .infinity)
                .disabled(loading || !auth.isConfigured)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
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

/// 同期の現在地（接続中／送信中／完了／エラー）と手動同期ボタン
private struct SyncCard: View {
    @ObservedObject private var sync = FirestoreSync.shared
    @ObservedObject private var repository = StashRepository.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                switch sync.status {
                case .syncing, .connecting:
                    ProgressView().controlSize(.small)
                default:
                    Text(statusEmoji)
                }
                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(isError ? Palette.error : Palette.onSurface)
                Spacer(minLength: 0)
            }

            Text(L.s(
                "sync_stats",
                repository.state.items.count,
                repository.state.collections.count
            ))
            .font(.caption)
            .foregroundStyle(Palette.onSurfaceVariant)
            .padding(.top, 6)

            Button(L.s("settings_sync_now")) { sync.syncNow() }
                .buttonStyle(.bordered)
                .tint(Palette.primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .disabled(sync.status == .syncing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var isError: Bool {
        if case .failure = sync.status { return true }
        return false
    }

    private var statusEmoji: String {
        switch sync.status {
        case .synced: return "✅"
        case .failure: return "⚠️"
        case .pending: return "🕒"
        default: return "☁️"
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
