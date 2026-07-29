import SwiftUI

/// アイテム詳細のボトムシート
struct DetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toast: ToastController

    let item: StashItem
    let collections: [StashCollection]

    @State private var tagInput = ""
    @State private var showDeleteConfirm = false
    @State private var showImageViewer = false
    @State private var showReport = false
    @State private var savingImage = false
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHandle()
                header

                // ボタンは本文・画像より先に置く。長い本文や大きい画像を先に出すと
                // 主要な操作がスクロールしないと届かなくなる
                PrimaryButton(title: L.s("action_open"), icon: Lucide.externalLink) {
                    openLink(item)
                    dismiss()
                }
                .padding(.top, 16)

                actions.padding(.top, 10)

                // 保存時に通信できなかった等でサムネイル・本文が空のままの場合の救済
                if item.imageUrl == nil || item.description == nil {
                    TextLink(text: L.s("detail_refetch"), icon: Lucide.refreshCw) {
                        StashRepository.shared.refetchMetadata(itemId: item.id)
                    }
                    .padding(.top, 12)

                    // 再取得しても直らないサイトがある（SNSはog:タグを自社の
                    // クローラにしか返さない等）。その受け皿を再取得の真下に置く。
                    // ただし試す前の第一候補は再取得なので、色を落として一段下げる
                    if ThumbnailReport.Form.isConfigured {
                        SubtleTextLink(text: L.s("report_thumbnail_action"), icon: Lucide.messageSquare) {
                            showReport = true
                        }
                    }
                }

                // SNSの投稿ではog:descriptionに本文が入る。記事ならリード文。
                // 長い場合は畳んでおき、タップで開く
                if let description = item.description {
                    ExpandableText(text: description).padding(.top, 16)
                }

                if let imageUrl = item.imageUrl {
                    preview(imageUrl: imageUrl).padding(.top, 14)
                }

                collectionSection.padding(.top, 18)
                tagSection.padding(.top, 18)

                Spacer(minLength: 26)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity)
        .background(Palette.bg)
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
        // 中間の高さ（半開き）で止まると、内側のスクロールとシートのドラッグが
        // 取り合って引っかかる。常に全開にして競合を無くす。
        // ただし上は必ず残す（元の一覧が見えないと「閉じれば戻れる」感覚が消える）
        .presentationDetents([.fraction(0.82)])
        .alert(L.s("delete_link_title"), isPresented: $showDeleteConfirm) {
            Button(L.s("action_cancel"), role: .cancel) {}
            Button(L.s("action_delete"), role: .destructive) {
                StashRepository.shared.deleteItem(id: item.id)
                toast.show(L.s("toast_deleted"))
                dismiss()
            }
        } message: {
            Text(item.title)
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            if let imageUrl = item.imageUrl {
                ImageViewerView(
                    imageUrl: imageUrl,
                    onDismiss: { showImageViewer = false },
                    onSave: { saveImage(imageUrl) }
                )
                .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showReport) {
            ThumbnailReportSheet(item: item)
                .environmentObject(toast)
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Thumbnail(item: item, size: 58, corner: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(PokkeType.titleSmall)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(L.s("detail_meta", item.siteName ?? item.host, relativeTime(item.savedAt)))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
                if item.openCount > 0 {
                    Text(L.plural("detail_reopen_count", item.openCount))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.accent2_600)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            StackedActionButton(
                icon: Lucide.archive,
                label: L.s(item.archived ? "detail_unarchive" : "detail_archive")
            ) {
                StashRepository.shared.setArchived(id: item.id, archived: !item.archived)
                toast.show(L.s(item.archived ? "toast_unarchived" : "toast_archived"))
                dismiss()
            }
            // URLのコピーは共有シート側にあるので置いていない
            StackedActionButton(icon: Lucide.share, label: L.s("detail_share")) {
                shareLink(item)
            }
            StackedActionButton(
                icon: Lucide.download,
                label: L.s("action_save"),
                // 画像が無ければ保存しようがないので押せなくする
                enabled: item.imageUrl != nil && !savingImage
            ) {
                if let imageUrl = item.imageUrl { saveImage(imageUrl) }
            }
            StackedActionButton(
                icon: Lucide.trash,
                label: L.s("action_delete"),
                contentColor: Palette.danger,
                borderColor: Palette.danger.opacity(0.3)
            ) {
                showDeleteConfirm = true
            }
        }
    }

    private func preview(imageUrl: String) -> some View {
        Button {
            showImageViewer = true
        } label: {
            ZStack {
                ServiceVisual.of(host: item.host).tint
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    if let image = phase.image {
                        // 切り抜かずに全体を見せる。Instagramの正方形画像などを
                        // 切り抜くと一部しか見えない
                        image.resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
            }
            // 高さを固定する。可変にすると画像の読み込み完了時に
            // シートの高さが変わり、スクロール位置が飛んで引っかかる
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                TapToExpandHint().padding(10)
            }
        }
        .buttonStyle(.plain)
    }

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.s("detail_collections"))
                .font(PokkeType.labelMedium)
                .foregroundStyle(Palette.neutral700)
            if collections.isEmpty {
                Text(L.s("detail_no_collections"))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(collections) { collection in
                        CollectionChip(
                            collection: collection,
                            selected: item.collectionId == collection.id
                        ) {
                            var updated = item
                            updated.collectionId = item.collectionId == collection.id ? nil : collection.id
                            StashRepository.shared.updateItem(updated)
                        }
                    }
                }
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.s("detail_tags"))
                .font(PokkeType.labelMedium)
                .foregroundStyle(Palette.neutral700)

            if !item.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(item.tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            var updated = item
                            updated.tags.removeAll { $0 == tag }
                            StashRepository.shared.updateItem(updated)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                PillField(focused: tagFieldFocused, height: 44) {
                    LucideIconView(icon: Lucide.tag, size: 15, color: Palette.neutral500)
                    TextField(L.s("detail_add_tag"), text: $tagInput)
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.accent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($tagFieldFocused)
                        .onSubmit(addTag)
                }
                Button(action: addTag) {
                    Text(L.s("action_add"))
                        .font(PokkeType.labelLarge)
                        .foregroundStyle(Palette.accent700)
                        .padding(.horizontal, 8)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^#", with: "", options: .regularExpression)
        if !tag.isEmpty, !item.tags.contains(tag) {
            var updated = item
            updated.tags.append(tag)
            StashRepository.shared.updateItem(updated)
        }
        tagInput = ""
    }

    /// 保存の結果はトーストで知らせる。ダウンロード中は二重タップを防ぐ
    private func saveImage(_ imageUrl: String) {
        savingImage = true
        Task {
            let ok = await ImageSaver.saveToPhotos(imageUrl: imageUrl, title: item.title)
            savingImage = false
            toast.show(L.s(ok ? "image_saved" : "image_save_failed"))
        }
    }
}

/// 所属中は淡いテラコッタ地＋枠。タップで出し入れする
private struct CollectionChip: View {
    let collection: StashCollection
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIconView(
                    icon: Lucide.collectionIcon(collection.icon),
                    size: 14,
                    color: color
                )
                Text(collection.name)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(selected ? Palette.accent100 : Palette.surface))
            .overlay(Capsule().stroke(selected ? Palette.accent : Palette.hairline, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.95))
    }

    private var color: Color { selected ? Palette.accent800 : Palette.neutral700 }
}

/// 「#タグ ✕」。タップすると外れる
private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Text("#\(tag)")
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.neutral800)
                LucideIconView(icon: Lucide.x, size: 12, color: Palette.neutral600)
            }
            .padding(.leading, 12)
            .padding(.trailing, 9)
            .frame(height: 32)
            .background(Capsule().fill(Palette.neutral200))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.s("action_delete") + " #\(tag)")
    }
}

/// アイコン付きのテキストリンク
private struct TextLink: View {
    let text: String
    let icon: Lucide.Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIconView(icon: icon, size: 15, color: Palette.accent700)
                Text(text)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.accent700)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// [TextLink] の控えめな版。
/// アクセント色を使わず字も一段小さくして、隣に並ぶ本命の操作より後ろに置く。
private struct SubtleTextLink: View {
    let text: String
    let icon: Lucide.Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIconView(icon: icon, size: 15, color: Palette.neutral500)
                Text(text)
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
            }
            // 字は小さいままでも指で押せるよう、上下の余白で触れる範囲を稼ぐ。
            // 左右は空けない。空けると真上のTextLinkとアイコンの頭が揃わなくなる
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
