import SwiftUI

/// リンク何件ごとにネイティブ広告を挟むか
private let adInterval = 6

/// ホーム一覧の行。ドメイン見出し・リンク・広告のいずれか
private enum HomeRow: Identifiable {
    case header(label: String, count: Int)
    case link(StashItem)
    case ad(slot: Int)

    var id: String {
        switch self {
        case let .header(label, _): return "header-\(label)"
        case let .link(item): return "item-\(item.id)"
        case let .ad(slot): return "ad-\(slot)"
        }
    }
}

/// 表示行を組み立てる。グループONならドメイン見出しを挟み、広告はリンクN件ごとに差し込む
private func buildHomeRows(items: [StashItem], groupByDomain: Bool) -> [HomeRow] {
    var rows: [HomeRow] = []
    var adSlot = 0
    var linkCount = 0

    func addLink(_ item: StashItem) {
        rows.append(.link(item))
        linkCount += 1
        if linkCount % adInterval == 0 {
            rows.append(.ad(slot: adSlot))
            adSlot += 1
        }
    }

    if groupByDomain {
        for group in DomainGrouping.group(items) {
            rows.append(.header(label: group.label, count: group.items.count))
            group.items.forEach(addLink)
        }
    } else {
        items.forEach(addLink)
    }
    return rows
}

/// ホーム: 未読/アーカイブ一覧
struct HomeScreen: View {
    let state: StashState
    let onItemTap: (StashItem) -> Void
    let onAddSamples: () -> Void

    @AppStorage("home.showArchived") private var showArchived = false
    @AppStorage("home.groupByDomain") private var groupByDomain = false
    @State private var pendingDelete: StashItem?

    private var listItems: [StashItem] {
        state.items
            .filter { $0.archived == showArchived }
            .sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        List {
            Section {
                Text("Pokke")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.onSurface)
                    .padding(.top, 8)
                    .plainRow()

                HStack(spacing: 8) {
                    FilterChipView(
                        label: L.s("filter_unread", state.items.filter(\.unread).count),
                        selected: !showArchived
                    ) { showArchived = false }
                    FilterChipView(
                        label: L.s("filter_archived", state.items.filter(\.archived).count),
                        selected: showArchived
                    ) { showArchived = true }
                }
                .plainRow()

                Toggle(L.s("group_by_site"), isOn: $groupByDomain)
                    .font(.subheadline)
                    .foregroundStyle(Palette.onSurface)
                    .tint(Palette.primary)
                    .plainRow()
            }

            if listItems.isEmpty {
                VStack(spacing: 12) {
                    Text(L.s(showArchived ? "home_empty_archived" : "home_empty"))
                        .font(.subheadline)
                        .foregroundStyle(Palette.onSurfaceVariant)
                    if !showArchived && state.items.isEmpty {
                        Button(L.s("add_samples"), action: onAddSamples)
                            .buttonStyle(.bordered)
                            .tint(Palette.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .plainRow()
            } else {
                ForEach(buildHomeRows(items: listItems, groupByDomain: groupByDomain)) { row in
                    switch row {
                    case let .header(label, count):
                        Text(L.s("group_header", DomainGrouping.labelEmoji(label), label, count))
                            .font(.subheadline.bold())
                            .foregroundStyle(Palette.primary)
                            .padding(.top, 6)
                            .plainRow()

                    case let .link(item):
                        ItemRow(
                            item: item,
                            collection: state.collections.first { $0.id == item.collectionId },
                            onTap: { onItemTap(item) }
                        )
                        .plainRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label(L.s("action_delete"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                pendingDelete = item
                            } label: {
                                Label(L.s("action_delete"), systemImage: "trash")
                            }
                        }

                    case .ad:
                        NativeAdCard().plainRow()
                    }
                }
            }

            // FABに隠れる分の余白
            Color.clear.frame(height: 80).plainRow()
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(Palette.appBackground)
        // スワイプは「削除の意思表示」までで、実際に消すのは確認してから（Android版と同じ）
        .confirmationDialog(
            L.s("delete_link_title"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button(L.s("action_delete"), role: .destructive) {
                StashRepository.shared.deleteItem(id: item.id)
                pendingDelete = nil
            }
            Button(L.s("action_cancel"), role: .cancel) { pendingDelete = nil }
        } message: { item in
            Text(item.title)
        }
    }
}

extension View {
    /// Listの行をカード用に素の状態へ戻す（区切り線・背景・既定の余白を消す）
    func plainRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}
