import SwiftUI

/// 「3日前」「3 days ago」のような相対時刻表示
func relativeTime(_ millis: EpochMillis) -> String {
    let minutes = Int((nowMillis() - millis) / 60_000)
    switch minutes {
    case ..<1:
        return L.s("time_just_now")
    case ..<60:
        return L.plural("time_minutes_ago", minutes)
    case ..<(60 * 24):
        return L.plural("time_hours_ago", minutes / 60)
    default:
        return L.plural("time_days_ago", minutes / (60 * 24))
    }
}

/// ブラウザで開く＋再訪カウント
@MainActor
func openLink(_ item: StashItem) {
    StashRepository.shared.markOpened(id: item.id)
    guard let url = URL(string: item.url) else { return }
    UIApplication.shared.open(url)
}

/// OGP画像 or 頭文字のサムネイル
struct Thumbnail: View {
    let item: StashItem
    var size: CGFloat = 56
    var corner: CGFloat = 12

    var body: some View {
        Group {
            if let imageUrl = item.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Palette.placeholderBg
            Text(item.host.prefix(1).uppercased())
                .font(.title2)
                .foregroundStyle(Palette.onSurfaceVariant)
        }
    }
}

/// リスト1行分のアイテムカード
struct ItemRow: View {
    let item: StashItem
    let collection: StashCollection?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                Thumbnail(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        if let collection {
                            Text(collection.emoji).font(.caption2)
                        }
                        Text(L.s("item_meta", item.host, relativeTime(item.savedAt)))
                            .font(.caption)
                            .foregroundStyle(Palette.onSurfaceVariant)
                            .lineLimit(1)
                        if item.unread {
                            Circle()
                                .fill(Palette.primary)
                                .frame(width: 7, height: 7)
                                .padding(.leading, 2)
                        }
                    }

                    if !item.tags.isEmpty {
                        Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(Palette.primary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardBackground()
    }
}

/// Material3の FilterChip 相当
struct FilterChipView: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(selected ? Palette.navy : Palette.onSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? Palette.primaryContainer : Color.clear)
                )
                .overlay(
                    Capsule().stroke(selected ? Palette.primary : Palette.outline, lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 空状態の案内
struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Palette.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

/// 画面右下に浮かせる「＋」ボタン（AndroidのFAB相当）
struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("＋")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Palette.primary))
                .shadow(color: Palette.slate.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

/// URL手入力シート
struct AddLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 保存できたら true を返す。false ならURLとして解釈できなかった
    let onAdd: (String) -> Bool

    @State private var text = ""
    @State private var showError = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L.s("add_link_placeholder"), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused)
                    .onChange(of: text) { _, _ in showError = false }

                if showError {
                    Text(L.s("add_link_invalid"))
                        .font(.caption)
                        .foregroundStyle(Palette.error)
                }

                Text(L.s("add_link_share_hint"))
                    .font(.caption)
                    .foregroundStyle(Palette.onSurfaceVariant)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Palette.appBackground)
            .navigationTitle(L.s("add_link_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.s("action_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("action_save")) {
                        if onAdd(text) { dismiss() } else { showError = true }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(260)])
        .onAppear { focused = true }
    }
}
