import SwiftUI

/// ＋ボタンから開く保存シート。
///
/// 主導線は他アプリの共有シートなので、まずその手順を大きく見せ、
/// URLの貼り付けは「それもできる」という位置づけで下に置いている。
struct SaveLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String) -> AddLinkResult

    /// 保存できなかった理由。URL不正と上限とで出す文言が違う
    private enum SaveError { case invalidUrl, limitReached }

    @State private var url = ""
    @State private var error: SaveError?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHandle()

            Text(L.s("add_link_title"))
                .font(PokkeType.titleMedium)
                .foregroundStyle(Palette.ink)

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Palette.surface)
                    LucideIconView(icon: Lucide.share, size: 19, color: Palette.accent700)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.s("save_link_lead"))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.accent900)
                    Text(L.s("save_link_steps"))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.accent800)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Corner.medium, style: .continuous)
                    .fill(Palette.accent100)
            )
            .padding(.top, 14)

            Text(L.s("save_link_or_paste"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .padding(.horizontal, 2)
                .padding(.top, 14)

            PillField(focused: focused) {
                LucideIconView(icon: Lucide.link, size: 17, color: Palette.neutral500)
                TextField(L.s("add_link_placeholder"), text: $url)
                    .font(PokkeType.labelLarge)
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(save)
                    .onChange(of: url) { _, _ in error = nil }
            }
            .padding(.top, 8)

            if let error {
                Text(
                    error == .limitReached
                        ? L.s("add_link_limit_reached", StashRepository.maxItems)
                        : L.s("add_link_invalid")
                )
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.top, 8)
            }

            PrimaryButton(title: L.s("save_link_submit"), height: 50, action: save)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
    }

    private func save() {
        switch onAdd(url) {
        case .saved: dismiss()
        case .limitReached: error = .limitReached
        case .invalidUrl: error = .invalidUrl
        }
    }
}
