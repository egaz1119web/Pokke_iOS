import SwiftUI

/// コレクション一覧（グリッド）→ タップで中身一覧
struct CollectionsScreen: View {
    let state: StashState
    @Binding var openedCollectionId: String?
    let onItemTap: (StashItem) -> Void
    let onBrowseLinks: () -> Void

    @State private var showCreate = false

    private var opened: StashCollection? {
        state.collections.first { $0.id == openedCollectionId }
    }

    var body: some View {
        ZStack {
            if let opened {
                CollectionDetail(
                    state: state,
                    collection: opened,
                    onBack: { openedCollectionId = nil },
                    onItemTap: onItemTap,
                    onBrowseLinks: onBrowseLinks
                )
            } else {
                list
            }

            if showCreate {
                CollectionDialog(existing: nil, onDismiss: { showCreate = false })
            }
        }
        .animation(.easeOut(duration: 0.2), value: showCreate)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: L.s("collections_title"))
                    .padding(.bottom, 16)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)],
                    spacing: 11
                ) {
                    ForEach(state.collections) { collection in
                        CollectionCard(
                            collection: collection,
                            count: state.items.filter { $0.collectionId == collection.id }.count
                        ) {
                            openedCollectionId = collection.id
                        }
                    }
                    NewCollectionCard { showCreate = true }
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.top, 18)
            .padding(.bottom, bottomContentPadding)
        }
        .scrollIndicators(.hidden)
    }
}

private struct CollectionCard: View {
    let collection: StashCollection
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                IconTile(
                    icon: Lucide.collectionIcon(collection.icon),
                    // 淡い地の上なのでアイコンの台は白の透過。地の色味が透けて馴染む
                    tint: Color.white.opacity(0.65),
                    foreground: Palette.ink,
                    size: 40,
                    iconSize: 20
                )
                Spacer(minLength: 12)
                Text(collection.name)
                    .font(PokkeType.bodyLarge)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(L.plural("item_count", count))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral700)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(collectionColor(collection.colorIndex))
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.pressScale())
    }
}

private struct NewCollectionCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                IconTile(
                    icon: Lucide.plus,
                    tint: Palette.ink.opacity(0.07),
                    foreground: Palette.neutral700,
                    size: 40,
                    iconSize: 20
                )
                Text(L.s("collection_new"))
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.neutral700)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 124)
            .padding(15)
            // 既存のカードと同じ形だが、破線と地無しで「まだ空の枠」だと分かるようにする
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        Palette.ink.opacity(0.25),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.pressScale())
    }
}

private struct CollectionDetail: View {
    let state: StashState
    let collection: StashCollection
    let onBack: () -> Void
    let onItemTap: (StashItem) -> Void
    let onBrowseLinks: () -> Void

    @State private var showEdit = false
    @State private var showAskAi = false
    @State private var aiAvailability: AiAvailability = currentAiAvailability()

    private var items: [StashItem] {
        state.items
            .filter { $0.collectionId == collection.id }
            .sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    header
                    // 中身が無いコレクションでは答える材料が無いので出さない
                    if showsAiEntryPoint(aiAvailability), !items.isEmpty {
                        AiAskBar(text: L.s("ai_ask_this_collection")) { showAskAi = true }
                    }
                    if items.isEmpty {
                        CollectionEmptyState(collection: collection, onBrowseLinks: onBrowseLinks)
                    } else {
                        ForEach(items) { item in
                            ItemRow(
                                item: item,
                                thumbnailSize: 56,
                                thumbnailCorner: 14,
                                showExcerpt: false
                            ) { onItemTap(item) }
                        }
                    }
                }
                .padding(.horizontal, screenPadding)
                .padding(.top, 18)
                .padding(.bottom, bottomContentPadding)
            }
            .scrollIndicators(.hidden)

            if showEdit {
                CollectionDialog(
                    existing: collection,
                    onDismiss: { showEdit = false },
                    // 削除するとこの画面が指すコレクションが消えるので、一覧まで戻す
                    onDeleted: { showEdit = false; onBack() }
                )
            }
        }
        .animation(.easeOut(duration: 0.2), value: showEdit)
        .onAppear { aiAvailability = currentAiAvailability() }
        .sheet(isPresented: $showAskAi) {
            AskAiSheet(
                scopeLabel: L.s("ai_scope_collection", collection.name, items.count),
                items: items,
                suggestions: [
                    L.s("ai_suggest_collection_summary"),
                    L.s("ai_suggest_collection_pick"),
                    L.s("ai_suggest_collection_oldest"),
                ]
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(
                icon: Lucide.chevronLeft,
                accessibilityLabel: L.s("action_back"),
                action: onBack
            )
            IconTile(
                icon: Lucide.collectionIcon(collection.icon),
                tint: collectionColor(collection.colorIndex),
                foreground: Palette.ink,
                size: 44,
                iconSize: 20
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(collection.name)
                    .font(PokkeType.titleLarge)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(L.plural("item_count", items.count))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral600)
            }
            Spacer(minLength: 0)
            // 削除もこの先の編集ダイアログの中。ここに置くと、
            // 戻るボタンのすぐ隣で取り返しのつかない操作ができてしまう
            CircleIconButton(
                icon: Lucide.pencil,
                accessibilityLabel: L.s("collection_edit"),
                iconSize: 17
            ) { showEdit = true }
        }
        .padding(.bottom, 6)
    }
}

private struct CollectionEmptyState: View {
    let collection: StashCollection
    let onBrowseLinks: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            IconTile(
                icon: Lucide.collectionIcon(collection.icon),
                tint: collectionColor(collection.colorIndex),
                foreground: Palette.ink,
                size: 78,
                iconSize: 32
            )
            Text(L.s("collection_empty_title"))
                .font(PokkeType.bodyLarge)
                .foregroundStyle(Palette.ink)
                .padding(.top, 16)
            Text(L.s("collection_empty_description"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)
                .padding(.top, 6)
            OutlinedPillButton(title: L.s("collection_browse_links"), action: onBrowseLinks)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 58)
        .padding(.horizontal, 24)
    }
}

/// コレクションの作成／編集ダイアログ（名前＋アイコン＋色）。
///
/// [existing] が nil なら新規作成。渡されていれば編集で、削除もここから行う。
/// 作成と編集で触る項目がまったく同じなので、画面を分けずに1つにしている。
private struct CollectionDialog: View {
    let existing: StashCollection?
    let onDismiss: () -> Void
    var onDeleted: () -> Void = {}

    @EnvironmentObject private var toast: ToastController
    @State private var name: String
    @State private var iconIndex: Int
    @State private var colorIndex: Int
    @FocusState private var nameFocused: Bool

    init(
        existing: StashCollection?,
        onDismiss: @escaping () -> Void,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.existing = existing
        self.onDismiss = onDismiss
        self.onDeleted = onDeleted
        _name = State(initialValue: existing?.name ?? "")
        _iconIndex = State(initialValue: existing
            .flatMap { CollectionIcons.all.firstIndex(of: CollectionIcons.normalize($0.icon)) } ?? 0)
        // 既存データは色が6色より多かった頃の番号を持っていることがある
        _colorIndex = State(initialValue: (existing?.colorIndex).map {
            let count = Palette.collectionColors.count
            return (($0 % count) + count) % count
        } ?? 0)
    }

    private var icon: String { CollectionIcons.all[iconIndex] }

    var body: some View {
        ZStack {
            // シート・ダイアログの背後を覆う幕
            Color(hex: 0x201E1D).opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L.s(existing == nil ? "collection_new" : "collection_edit"))
                        .font(PokkeType.titleMedium)
                        .foregroundStyle(Palette.ink)

                    HStack(spacing: 12) {
                        // 選んだアイコンと色が実際にどう見えるかをそのまま出す。
                        // グリッドの選択枠だけだと分かりにくいので、ここが答え合わせになる
                        IconTile(
                            icon: Lucide.collectionIcon(icon),
                            tint: collectionColor(colorIndex),
                            foreground: Palette.ink,
                            size: 52,
                            iconSize: 22
                        )
                        TextField(L.s("collection_name_placeholder"), text: $name)
                            .font(PokkeType.labelLarge)
                            .foregroundStyle(Palette.ink)
                            .tint(Palette.accent)
                            .focused($nameFocused)
                            .padding(.horizontal, 14)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: Corner.small, style: .continuous)
                                    .fill(Palette.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Corner.small, style: .continuous)
                                    .stroke(nameFocused ? Palette.accent : Palette.hairline, lineWidth: 1.5)
                            )
                    }
                    .padding(.top, 16)

                    DialogSectionLabel(text: L.s("collection_icon"))
                        .padding(.top, 16)
                    IconGrid(selected: $iconIndex).padding(.top, 8)

                    DialogSectionLabel(text: L.s("collection_color"))
                        .padding(.top, 16)
                    HStack(spacing: 9) {
                        ForEach(Palette.collectionColors.indices, id: \.self) { index in
                            ColorDot(
                                color: Palette.collectionColors[index],
                                selected: index == colorIndex
                            ) { colorIndex = index }
                        }
                    }
                    .padding(.top, 8)

                    HStack(spacing: 8) {
                        if let existing {
                            // 削除は左端に離して置く。保存の隣だと押し間違えやすい
                            DialogTextButton(title: L.s("action_delete"), color: Palette.danger) {
                                StashRepository.shared.deleteCollection(id: existing.id)
                                toast.show(L.s("toast_deleted"))
                                onDeleted()
                            }
                        }
                        Spacer(minLength: 0)
                        DialogTextButton(title: L.s("action_cancel"), action: onDismiss)
                        DialogPrimaryButton(
                            title: L.s(existing == nil ? "action_create" : "action_save"),
                            enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            action: save
                        )
                    }
                    .padding(.top, 20)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: Corner.extraLarge, style: .continuous)
                        .fill(Palette.bg)
                )
                .softShadow(.lg)
                .padding(.horizontal, 24)
                // 小さい画面・大きい文字設定でも全部触れるようスクロールさせる
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .transition(.opacity)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing {
            var updated = existing
            updated.name = trimmed
            updated.icon = icon
            updated.colorIndex = colorIndex
            StashRepository.shared.updateCollection(updated)
            toast.show(L.s("toast_saved"))
        } else {
            StashRepository.shared.addCollection(name: trimmed, icon: icon, colorIndex: colorIndex)
            toast.show(L.s("toast_created"))
        }
        onDismiss()
    }
}

private struct DialogSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PokkeType.labelMedium)
            .foregroundStyle(Palette.neutral700)
    }
}

private struct DialogTextButton: View {
    let title: String
    var color: Color = Palette.neutral700
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PokkeType.labelLarge)
                .foregroundStyle(color)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct DialogPrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PokkeType.labelLarge)
                .foregroundStyle(enabled ? Color.white : Palette.neutral600)
                .padding(.horizontal, 24)
                .frame(height: 44)
                .background(Capsule().fill(enabled ? Palette.accent : Palette.neutral300))
                .softShadow(.sm)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 12種のアイコンを6列×2行で並べる
private struct IconGrid: View {
    @Binding var selected: Int

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 6),
            spacing: 7
        ) {
            ForEach(CollectionIcons.all.indices, id: \.self) { index in
                IconCell(icon: CollectionIcons.all[index], selected: index == selected) {
                    selected = index
                }
            }
        }
    }

    private struct IconCell: View {
        let icon: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    RoundedRectangle(cornerRadius: Corner.small, style: .continuous)
                        .fill(selected ? Palette.accent100 : Palette.ink.opacity(0.05))
                    LucideIconView(
                        icon: Lucide.collectionIcon(icon),
                        size: 19,
                        color: selected ? Palette.accent700 : Palette.neutral700
                    )
                }
                // マスは正方形。高さを指定しないと縦に潰れる
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: Corner.small, style: .continuous)
                        .stroke(selected ? Palette.accent : Color.clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ColorDot: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                // 淡い色どうしの差が小さいので、枠だけでなくチェックも出す
                if selected {
                    LucideIconView(icon: Lucide.check, size: 15, color: Palette.ink)
                }
            }
            .frame(width: 38, height: 38)
            .overlay(Circle().stroke(selected ? Palette.ink : Color.clear, lineWidth: 2.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
