import SwiftUI

/// 選んだリンクの入れ先コレクションを選ぶシート。ホームの編集モードから開く。
///
/// 1件が属せるコレクションは1つなので、ここでするのは「入れ先を1つ選ぶ」ことだけ。
/// 外す・入れ替えるのは1件ずつの話なので詳細シートのチップに任せてある。
struct CollectionPickSheet: View {
    let selectedCount: Int
    let collections: [StashCollection]
    let allItems: [StashItem]
    let onPick: (StashCollection) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                SheetHandle()

                Text(L.s("edit_add_to_collection"))
                    .font(PokkeType.titleSmall)
                    .foregroundStyle(Palette.ink)
                Text(L.plural("edit_collection_pick_message", selectedCount))
                    .font(PokkeType.bodySmall)
                    .foregroundStyle(Palette.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)

                ForEach(collections) { collection in
                    CollectionPickRow(
                        collection: collection,
                        count: allItems.filter { $0.collectionId == collection.id }.count
                    ) {
                        onPick(collection)
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
        .presentationDetents([.fraction(0.55), .large])
    }
}

/// 入れ先の1行。今そこに何件入っているかまで出して、入れる前に量が分かるようにする
private struct CollectionPickRow: View {
    let collection: StashCollection
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                IconTile(
                    icon: Lucide.collectionIcon(collection.icon),
                    tint: collectionColor(collection.colorIndex),
                    foreground: Palette.ink,
                    size: 38,
                    iconSize: 18,
                    cornerRadius: 11
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(collection.name)
                        .font(PokkeType.bodyLarge)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(L.plural("item_count", count))
                        .font(PokkeType.bodySmall)
                        .foregroundStyle(Palette.neutral600)
                }
                Spacer(minLength: 0)
                LucideIconView(icon: Lucide.chevronRight, size: 16, color: Palette.neutral400)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: Corner.medium, style: .continuous)
                    .fill(Palette.surface)
            )
            .contentShape(RoundedRectangle(cornerRadius: Corner.medium, style: .continuous))
        }
        .buttonStyle(.pressScale())
    }
}
