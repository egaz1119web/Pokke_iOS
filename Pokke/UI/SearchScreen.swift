import SwiftUI

/// タイトル・URL・タグの横断検索＋タグで絞り込み
struct SearchScreen: View {
    let state: StashState
    let onItemTap: (StashItem) -> Void

    @State private var query = ""
    @State private var selectedTag: String?
    @FocusState private var fieldFocused: Bool

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
                    || (item.description?.localizedCaseInsensitiveContains(q) ?? false)
                    || item.tags.contains { $0.localizedCaseInsensitiveContains(q) }
                let matchesTag = selectedTag == nil || item.tags.contains(selectedTag!)
                return matchesQuery && matchesTag
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ScreenTitle(text: L.s("search_title"))

                SearchField(query: $query, focused: $fieldFocused)
                    .padding(.top, 4)

                if !allTags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(allTags, id: \.self) { tag in
                            ServiceChip(
                                label: "#\(tag)",
                                count: state.items.filter { $0.tags.contains(tag) }.count,
                                selected: selectedTag == tag
                            ) {
                                selectedTag = selectedTag == tag ? nil : tag
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                SectionLabel(
                    // 未入力のうちは件数ではなく「最近保存したリンク」として見せる。
                    // 全件が出ているだけなので、ヒット数を出しても意味が無い
                    text: query.trimmingCharacters(in: .whitespaces).isEmpty && selectedTag == nil
                        ? L.s("search_recent")
                        : L.s("search_results_count", results.count)
                )
                .padding(.top, 8)

                if results.isEmpty {
                    EmptyState(
                        icon: Lucide.inbox,
                        message: L.s(state.items.isEmpty ? "search_empty_nothing_saved" : "search_no_results")
                    )
                } else {
                    ForEach(results) { item in
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
        .scrollDismissesKeyboard(.interactively)
    }
}

/// 白地のピル型の検索欄。フォーカスでテラコッタの枠になる
private struct SearchField: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        PillField(focused: focused.wrappedValue) {
            LucideIconView(icon: Lucide.search, size: 18, color: Palette.neutral500)
            TextField(L.s("search_placeholder"), text: $query)
                .font(PokkeType.labelLarge)
                .foregroundStyle(Palette.ink)
                .tint(Palette.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focused)
        }
    }
}

/// 折り返して並ぶチップ列。Composeの `FlowRow` 相当
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > width {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
