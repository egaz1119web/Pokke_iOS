import SwiftUI

/// タイトル・URL・タグの横断検索＋タグで絞り込み
struct SearchScreen: View {
    let state: StashState
    let onItemTap: (StashItem) -> Void

    @State private var query = ""
    @State private var selectedTag: String?
    @FocusState private var fieldFocused: Bool
    @State private var showAskAi = false
    @ObservedObject private var ai = AiAssistant.shared
    @State private var tagsExpanded = false
    /// タグを全部並べるのに要した行数。FlowLayoutが実測して知らせてくる
    @StateObject private var tagRowCount = FlowRowCount()

    /// タグが増えるほど検索結果が下に押し出されて見にくくなるので、
    /// 既定ではこの行数までに抑えて残りは展開で見せる
    private let collapsedTagRows = 3

    private var allTags: [String] {
        Array(Set(state.items.flatMap(\.tags))).sorted()
    }

    /// 開閉チップを出すか。3行に収まっているうちは要らない。
    /// 展開中は「閉じる」として必要なので、畳めるかどうかとは別に見る
    private var showsTagToggle: Bool {
        tagsExpanded || tagRowCount.rows > collapsedTagRows
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

                // 語が合うものを探すのが検索なら、こちらは「何が入っているか」を聞く口。
                // 保存が0件だと答える材料が無いので出さない
                if showsAiEntryPoint(ai.availability), !state.items.isEmpty {
                    AiAskBar(text: L.s("ai_ask_all_links")) { showAskAi = true }
                        .padding(.top, 4)
                }

                if !allTags.isEmpty {
                    // 開閉のチップはタグの列には混ぜず、下に独立して置く。
                    // 列の中に入れると畳んでいる間その分のタグが押し出されて見えなくなる
                    VStack(alignment: .leading, spacing: 8) {
                        FlowLayout(
                            spacing: 8,
                            maxRows: tagsExpanded ? nil : collapsedTagRows,
                            rowCount: tagRowCount
                        ) {
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
                        .clipped()

                        if showsTagToggle {
                            TagToggleChip(expanded: tagsExpanded) {
                                withAnimation(.easeInOut(duration: 0.2)) { tagsExpanded.toggle() }
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
                            showExcerpt: false,
                            showUnreadDot: false
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
        .task { await AiAssistant.shared.probeIfNeeded() }
        .sheet(isPresented: $showAskAi) {
            AskAiSheet(
                scopeLabel: L.s("ai_scope_all_links", state.items.count),
                items: state.items,
                suggestions: [
                    L.s("ai_suggest_all_topics"),
                    L.s("ai_suggest_all_recent"),
                    L.s("ai_suggest_all_pick"),
                ],
                // 検索語を入れたまま開いたなら、それをそのまま質問の下書きにする
                initialQuestion: query.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
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

/// [FlowLayout] が実測した行数を受け取る箱。
///
/// クロージャで受けようとすると2つ問題が出る。`Layout` は `Sendable` を要求するので
/// `@Sendable` が必要になり、さらに引数の最後がクロージャだと
/// `FlowLayout(spacing: 8) { チップ… }` の中身がそちらの引数として解決されてしまう。
/// `@MainActor` のクラスなら暗黙に `Sendable` で、引数の型も関数ではないので両方避けられる。
@MainActor
final class FlowRowCount: ObservableObject {
    @Published fileprivate(set) var rows = 0

    fileprivate func update(_ value: Int) {
        // 同じ値で入れ直すとレイアウトが延々と走り続ける
        if rows != value { rows = value }
    }
}

/// 折り返して並ぶチップ列。Composeの `FlowRow` 相当。
///
/// `maxRows` を渡すとその行数までしか見せない。行を隠す判断をレイアウト側で
/// 済ませているのが要点で、外から `GeometryReader` で高さを測って
/// `frame(height:)` で切る方式にすると、**制約後の高さを測ってしまう**ため
/// 「もう3行に収まっている」と誤判定して二度と展開できなくなる。
///
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// 表示する行数の上限。nil なら全部見せる
    var maxRows: Int?
    /// 全部並べるのに要した行数の受け取り先。開閉チップを出すかの判定に使う
    var rowCount: FlowRowCount?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = arrange(subviews: subviews, in: width)
        report(rows.count)
        let visible = visibleRows(rows)
        let height = visible.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, visible.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, in: bounds.width)
        let shown = visibleRows(rows).count
        var y = bounds.minY
        for (rowIndex, row) in rows.enumerated() {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // 上限を超えた行は画面の遥か上へ逃がす。返した高さの中に置くと
                // clipped() をすり抜けたタップを拾ってしまうことがあるため、
                // スクロール領域の外まで離す
                let position = rowIndex < shown
                    ? CGPoint(x: x, y: y)
                    : CGPoint(x: bounds.minX, y: bounds.minY - 10_000)
                subviews[index].place(at: position, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            if rowIndex < shown { y += row.height + spacing }
        }
    }

    private func visibleRows(_ rows: [Row]) -> [Row] {
        guard let maxRows else { return rows }
        return Array(rows.prefix(maxRows))
    }

    /// レイアウトの最中に状態を変えると警告になるので、次の実行に回す
    private func report(_ count: Int) {
        guard let rowCount else { return }
        Task { @MainActor in rowCount.update(count) }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extended = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, extended > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// タグ一覧の開閉チップ。[ServiceChip] と同じ高さにしてタグの列に馴染ませる
private struct TagToggleChip: View {
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(L.s(expanded ? "search_tags_show_less" : "search_tags_show_more"))
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.accent700)
                LucideIconView(
                    icon: expanded ? Lucide.chevronUp : Lucide.chevronDown,
                    size: 14,
                    color: Palette.accent700
                )
            }
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(Capsule().fill(Palette.accent100))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.95))
    }
}
