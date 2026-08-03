import SwiftUI

/// 保存してからしばらくたったリンクをまとめて片付けるシート。
///
/// **既定は全部にチェックが入っている**（＝全部消す）。1件ずつ選ばせると、
/// 整理したい人ほど手数が増える。残したいものだけ外してもらう向きにしてある。
///
/// 並びは古い順。いちばん長く寝かせたものから判断できる方が、外す判断が早い。
struct CleanupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toast: ToastController

    /// 対象（`OldItems.stale` で作った古い順の一覧）
    let items: [StashItem]

    /// チェックを外した＝残すもの。持ち方を「消す方」ではなく「残す方」にすると、
    /// 初期状態（全選択）が空集合になり、全解除との往復でも取り違えが起きない
    @State private var keptIds: Set<String> = []
    @State private var showConfirm = false
    /// 開いた時点の写し。開いている間にクラウド同期で古いリンクが増えても、
    /// 一度も見ていない行がチェック済みのまま削除に混ざらないようにする
    @State private var snapshot: [StashItem]?

    private var shown: [StashItem] { snapshot ?? items }

    private var selected: [StashItem] {
        shown.filter { !keptIds.contains($0.id) }
    }

    private var allCleared: Bool { keptIds.count >= shown.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                SheetHandle()

                Text(L.s("cleanup_title"))
                    .font(PokkeType.titleSmall)
                    .foregroundStyle(Palette.ink)
                Text(L.s("cleanup_description", OldItems.thresholdDays, shown.count))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                HStack(spacing: 10) {
                    Text(L.s("cleanup_selected_count", selected.count))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.neutral700)
                    Spacer(minLength: 0)
                    Button {
                        // 全部残す（全解除）→ もう一度押すと全部消す（全選択）へ戻る
                        keptIds = allCleared ? [] : Set(shown.map(\.id))
                    } label: {
                        Text(L.s(allCleared ? "cleanup_select_all" : "cleanup_clear_all"))
                            .font(PokkeType.labelMedium)
                            .foregroundStyle(Palette.accent700)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)

                ForEach(shown) { item in
                    CleanupRow(item: item, checked: !keptIds.contains(item.id)) {
                        if keptIds.contains(item.id) {
                            keptIds.remove(item.id)
                        } else {
                            keptIds.insert(item.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .background(Palette.bg)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
        .presentationDetents([.fraction(0.9)])
        // 削除は一覧をスクロールし終えなくても押せるところに置く。
        // 下端に固定しておくと、外した件数を見ながらいつでも決められる
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                PrimaryButton(
                    title: L.s("cleanup_delete_action", selected.count),
                    icon: Lucide.trash,
                    enabled: !selected.isEmpty
                ) {
                    showConfirm = true
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .background(Palette.bg)
        }
        // 一括削除は取り消せない。件数を出してもう一度だけ確かめる
        .alert(L.s("cleanup_confirm_title"), isPresented: $showConfirm) {
            Button(L.s("action_cancel"), role: .cancel) {}
            Button(L.s("action_delete"), role: .destructive, action: deleteSelected)
        } message: {
            Text(L.s("cleanup_confirm_message", selected.count))
        }
        .toastOverlay(toast)
        .onAppear { if snapshot == nil { snapshot = items } }
    }

    private func deleteSelected() {
        let count = selected.count
        StashRepository.shared.deleteItems(ids: selected.map(\.id))
        dismiss()
        toast.show(L.s("cleanup_deleted", count))
    }
}

/// 整理一覧の1行。行のどこを押してもチェックが入れ替わる
private struct CleanupRow: View {
    let item: StashItem
    let checked: Bool
    let onToggle: () -> Void

    var body: some View {
        PokkeCard(padding: 10, action: onToggle) {
            HStack(spacing: 11) {
                CheckBox(checked: checked)
                Thumbnail(item: item, size: 46, corner: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(PokkeType.bodyMedium)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(item.host)
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(Palette.neutral600)
                            .lineLimit(1)
                            .layoutPriority(-1)
                        Text("・")
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(Palette.neutral400)
                        Text(relativeTime(item.savedAt))
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(Palette.neutral600)
                            .fixedSize()
                        // アーカイブ済みも対象に含めているので、どちらなのかは見せておく
                        if item.archived {
                            LucideIconView(icon: Lucide.archive, size: 12, color: Palette.neutral500)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        // 残す側に倒した行は薄くして、消える行との違いを一目で分かるようにする
        .opacity(checked ? 1 : 0.55)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}

/// 角丸のチェックボックス。入っているときだけテラコッタで塗る
private struct CheckBox: View {
    let checked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(checked ? Palette.accent : Palette.surface)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(checked ? Palette.accent : Palette.neutral400, lineWidth: 1.5)
            if checked {
                LucideIconView(icon: Lucide.check, size: 13, color: .white)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// ホームに出す「古いリンクがたまっています」の知らせ。
///
/// 保存の上限が近いことの知らせ（`LimitBanner`）と違って急ぎではないので、
/// 閉じられるようにしてある（閉じると `OldItems.snoozeMs` のあいだ出ない）。
struct CleanupBanner: View {
    let count: Int
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIconView(icon: Lucide.clock, size: 16, color: Palette.accent2_700)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(L.s("cleanup_notice", OldItems.thresholdDays, count))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.accent2_800)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onOpen) {
                    Text(L.s("cleanup_notice_action"))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.accent2_700)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                LucideIconView(icon: Lucide.x, size: 14, color: Palette.accent2_700)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.s("action_close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Corner.medium, style: .continuous)
                .fill(Palette.accent2_100)
        )
    }
}
