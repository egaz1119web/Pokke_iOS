import SwiftUI

let emojiChoices = ["📚", "🍳", "🎮", "💡", "🎧", "✈️", "🛍️", "🏃", "🎬", "💼", "🐈", "⭐"]

/// コレクション一覧（グリッド）→ タップで中身一覧
struct CollectionsScreen: View {
    let state: StashState
    let onItemTap: (StashItem) -> Void
    @Binding var showCreate: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(state.collections) { collection in
                        NavigationLink(value: collection.id) {
                            collectionCard(collection)
                        }
                        .buttonStyle(.plain)
                    }
                    newCollectionCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .background(Palette.appBackground)
            .navigationTitle(L.s("collections_title"))
            .navigationDestination(for: String.self) { collectionId in
                CollectionDetail(
                    state: state,
                    collectionId: collectionId,
                    onItemTap: onItemTap
                )
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateCollectionSheet()
        }
    }

    private func collectionCard(_ collection: StashCollection) -> some View {
        let count = state.items.filter { $0.collectionId == collection.id }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(collection.emoji).font(.system(size: 32))
            Text(collection.name)
                .font(.headline)
                .foregroundStyle(Palette.slate)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(L.plural("item_count", count))
                .font(.caption)
                .foregroundStyle(Palette.slate.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground(fill: Palette.collectionColor(collection.colorIndex))
    }

    private var newCollectionCard: some View {
        Button { showCreate = true } label: {
            VStack(spacing: 8) {
                Text("＋")
                    .font(.system(size: 32))
                    .foregroundStyle(Palette.primary)
                Text(L.s("collection_new"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
}

private struct CollectionDetail: View {
    @Environment(\.dismiss) private var dismiss
    let state: StashState
    let collectionId: String
    let onItemTap: (StashItem) -> Void

    private var collection: StashCollection? {
        state.collections.first { $0.id == collectionId }
    }

    private var items: [StashItem] {
        state.items
            .filter { $0.collectionId == collectionId }
            .sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        ScrollView {
            if items.isEmpty {
                EmptyHint(text: L.s("collection_empty"))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        ItemRow(item: item, collection: nil, onTap: { onItemTap(item) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
        .background(Palette.appBackground)
        .navigationTitle(collection.map { "\($0.emoji) \($0.name)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L.s("action_delete"), role: .destructive) {
                    StashRepository.shared.deleteCollection(id: collectionId)
                    dismiss()
                }
                .foregroundStyle(Palette.error)
            }
        }
    }
}

/// コレクション作成シート（名前＋絵文字＋色）
private struct CreateCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emojiIndex = 0
    @State private var colorIndex = 0

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 選んだ絵文字・色・名前が実際にどう見えるかをそのまま出す。
                    // 絵文字グリッドの選択枠だけだと分かりにくいので、ここが答え合わせになる
                    preview

                    TextField(L.s("collection_name_placeholder"), text: $name)
                        .textFieldStyle(.roundedBorder)

                    Text(L.s("collection_emoji")).font(.subheadline.weight(.medium))
                    emojiGrid

                    Text(L.s("collection_color")).font(.subheadline.weight(.medium))
                    colorRow
                }
                .padding(20)
            }
            .background(Palette.appBackground)
            .navigationTitle(L.s("collection_new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.s("action_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.s("action_create")) {
                        StashRepository.shared.addCollection(
                            name: trimmedName,
                            emoji: emojiChoices[emojiIndex],
                            colorIndex: colorIndex
                        )
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    /// 作成後のコレクションカードと同じ見た目のプレビュー
    private var preview: some View {
        HStack(spacing: 12) {
            Text(emojiChoices[emojiIndex]).font(.system(size: 30))
            Text(trimmedName.isEmpty ? L.s("collection_preview_placeholder") : name)
                .font(.headline)
                .foregroundStyle(trimmedName.isEmpty ? Palette.slate.opacity(0.45) : Palette.slate)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.collectionColor(colorIndex))
        )
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(emojiChoices.indices, id: \.self) { index in
                let isSelected = index == emojiIndex
                Button { emojiIndex = index } label: {
                    Text(emojiChoices[index])
                        .font(.system(size: isSelected ? 24 : 20))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Palette.primaryContainer : Palette.surfaceVariant.opacity(0.5))
                        )
                        // 選択中は太い枠で囲う。primaryContainer と surfaceVariant は
                        // どちらも淡い青で塗りつぶしの差がほとんど出ないため、枠が実質の目印
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isSelected ? Palette.primary : Palette.outline.opacity(0.4),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    private var colorRow: some View {
        // 8色を4＋4の2段に割る（1段には収まらない）
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(Palette.collectionColors.indices, id: \.self) { index in
                let isSelected = index == colorIndex
                Button { colorIndex = index } label: {
                    ZStack {
                        // 選択中はリング＋チェックの二重表示にする
                        Circle()
                            .fill(Palette.collectionColors[index])
                            .frame(width: isSelected ? 28 : 36, height: isSelected ? 28 : 36)
                        if isSelected {
                            Circle()
                                .stroke(Palette.primary, lineWidth: 2)
                                .frame(width: 36, height: 36)
                            Text("✓")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.slate)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}
