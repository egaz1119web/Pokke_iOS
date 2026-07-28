import SwiftUI

/// タイトル・URL・タグの横断検索＋タグで絞り込み
struct SearchScreen: View {
    let state: StashState
    let onItemTap: (StashItem) -> Void

    @State private var query = ""
    @State private var selectedTag: String?

    private var allTags: [String] {
        Array(Set(state.items.flatMap(\.tags))).sorted()
    }

    private var results: [StashItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.items
            .filter { item in
                let matchesQuery = q.isEmpty
                    || item.title.localizedCaseInsensitiveContains(q)
                    || item.url.localizedCaseInsensitiveContains(q)
                    || item.tags.contains { $0.localizedCaseInsensitiveContains(q) }
                let matchesTag = selectedTag == nil || item.tags.contains(selectedTag!)
                return matchesQuery && matchesTag
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.s("search_title"))
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.onSurface)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                Text("🔍")
                TextField(L.s("search_placeholder"), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.outline, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface)
                    )
            )
            .padding(.horizontal, 16)

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allTags, id: \.self) { tag in
                            FilterChipView(label: "#\(tag)", selected: selectedTag == tag) {
                                selectedTag = selectedTag == tag ? nil : tag
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }

            if results.isEmpty {
                EmptyHint(
                    text: L.s(state.items.isEmpty ? "search_empty_nothing_saved" : "search_no_results")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { item in
                            ItemRow(
                                item: item,
                                collection: state.collections.first { $0.id == item.collectionId },
                                onTap: { onItemTap(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.appBackground)
    }
}
