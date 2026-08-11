import SwiftUI

/// リンク何件ごとにネイティブ広告を挟むか
private let adInterval = 6

/// ホーム一覧の行。リンクか広告のいずれか
private enum HomeRow: Identifiable {
    case link(StashItem)
    case ad(Int)

    var id: String {
        switch self {
        case let .link(item): return "item-\(item.id)"
        case let .ad(slot): return "ad-\(slot)"
        }
    }
}

/// 表示行を組み立てる。広告はリンクN件ごとに差し込む
private func buildHomeRows(_ items: [StashItem]) -> [HomeRow] {
    var rows: [HomeRow] = []
    var adSlot = 0
    for (index, item) in items.enumerated() {
        rows.append(.link(item))
        if (index + 1) % adInterval == 0 {
            rows.append(.ad(adSlot))
            adSlot += 1
        }
    }
    return rows
}

/// ホーム上部の絞り込み。
///
/// お気に入りはアーカイブとは別の軸なので、片付けたぶんも含めて全部並べる
/// （「残したい」と「読み終えた」は両立する）。
private enum HomeFilter: CaseIterable {
    case inbox, favorite, archived

    func matches(_ item: StashItem) -> Bool {
        switch self {
        case .inbox: return !item.archived
        case .favorite: return item.favorite
        case .archived: return item.archived
        }
    }

    /// ピルに出す件数。「未読」だけは並ぶ件数（未アーカイブ全部）ではなく、
    /// まだ開いていない数を出す — 知りたいのは残りの量なので
    func count(in items: [StashItem]) -> Int {
        switch self {
        case .inbox: return items.filter(\.unread).count
        case .favorite: return items.filter(\.favorite).count
        case .archived: return items.filter(\.archived).count
        }
    }
}

/// ホーム: 未読/お気に入り/アーカイブ一覧
struct HomeScreen: View {
    let state: StashState
    let onItemTap: (StashItem) -> Void
    let onShowGuide: () -> Void
    let onAddLink: () -> Void
    let onCleanup: () -> Void
    /// スポットライトで指す1件。案内が出ていないときは nil
    var highlightItemId: String?

    @ObservedObject private var prefs = AppPrefs.shared
    @EnvironmentObject private var toast: ToastController
    @State private var filter: HomeFilter = .inbox
    /// 選択中サービスのラベル。nil は「すべて」。スワイプでもチップでも同じ状態を見る
    @State private var selectedService: String?

    /// 長押しで入る編集モード。まとめて選んで一度に片付けるためだけの状態
    @State private var editing = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var showCollectionPick = false

    private var visibleItems: [StashItem] {
        state.items
            .filter(filter.matches)
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// 消えたリンク（他端末との同期など）が選択に残らないようにする
    private var selectedItems: [StashItem] {
        state.items.filter { selectedIds.contains($0.id) }
    }

    /// 整理の対象になる件数（アーカイブ済みも含む全体で数える）
    private var staleCount: Int {
        OldItems.stale(items: state.items, now: nowMillis()).count
    }

    private var showsCleanupNotice: Bool {
        OldItems.showsNotice(
            staleCount: staleCount,
            snoozedAt: prefs.cleanupSnoozedAt,
            now: nowMillis()
        )
    }

    var body: some View {
        let groups = DomainGrouping.group(visibleItems)
        // 各ページのサービスラベル。先頭(nil)が「すべて」
        let pages: [String?] = [nil] + groups.map(\.label)

        VStack(spacing: 0) {
            // ヘッダーはスワイプで動かさない。タブがページと一緒に流れると
            // 今どこにいるのかが分からなくなる
            Group {
                if editing {
                    // 編集中は絞り込みや表示切替を引っ込める。選んだものが見えなくなる操作が
                    // 選択と隣り合ってしまうため。ロゴと右上の丸ボタンは通常時と同じ位置に残し、
                    // 段数も揃えてあるので、入っても一覧の位置はほとんど動かない
                    EditHeader(
                        selectedCount: selectedItems.count,
                        pageItems: items(for: selectedService, groups: groups),
                        selectedIds: $selectedIds,
                        // 入れ先が1つも無いなら押せても行き先が無い。サービスチップと同じく、
                        // 中身が無い操作は出さない
                        canAddToCollection: !state.collections.isEmpty,
                        onAddToCollection: { showCollectionPick = true },
                        onDelete: { showDeleteConfirm = true },
                        onExit: exitEditing
                    )
                } else {
                    HomeHeader(
                        state: state,
                        filter: $filter,
                        groups: groups,
                        selectedService: $selectedService,
                        onAddLink: onAddLink
                    )
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.top, 18)

            // 知らせは一覧の外に置くので、下にも余白を持たせる。
            // ヘッダーの下余白（12pt）は知らせの上に付くだけなので、これが無いと
            // 知らせが1件目のカードにくっついて、同じ塊のように見えてしまう
            let noticePadding = EdgeInsets(top: 12, leading: screenPadding, bottom: 12, trailing: screenPadding)

            // 上限に当たってから知るのでは遅い。手前から残りを見せておく。
            // 知らせはどれも「今すぐでなくてよい話」なので、片付けの最中には割り込ませない
            let remaining = StashRepository.maxItems - state.items.count
            if !editing, remaining <= StashRepository.limitWarningRemaining {
                LimitBanner(remaining: remaining)
                    .padding(noticePadding)
            }

            // 寝かせたままのリンクがたまってきたら整理をすすめる。
            // 上限の知らせと同時に出ると押し付けがましいので、そちらを優先する
            if !editing, remaining > StashRepository.limitWarningRemaining, showsCleanupNotice {
                CleanupBanner(count: staleCount, onOpen: onCleanup) {
                    prefs.snoozeCleanupNotice()
                }
                .padding(noticePadding)
            }

            TabView(selection: $selectedService) {
                ForEach(pages, id: \.self) { label in
                    ItemPage(
                        items: items(for: label, groups: groups),
                        viewMode: prefs.viewMode,
                        filter: filter,
                        editing: editing,
                        selectedIds: selectedIds,
                        onItemTap: { item in
                            if editing {
                                toggle(item)
                            } else {
                                onItemTap(item)
                            }
                        },
                        onItemLongPress: { item in
                            // 長押しがそのまま1件目の選択になる。入ってから選び直させると、
                            // 「押したのに何も起きない」ように見える
                            editing = true
                            toggle(item)
                        },
                        onShowGuide: onShowGuide,
                        // 同じ1件が「すべて」とサービス別の両方に並ぶので、
                        // 穴が二重に登録されないよう「すべて」の側だけで指す
                        highlightItemId: label == nil ? highlightItemId : nil
                    )
                    .tag(label)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        // サービスが消えてページが無くなったときは「すべて」へ逃がす
        .onChange(of: pages) { _, current in
            if let selected = selectedService, !current.contains(selected) { selectedService = nil }
        }
        // 絞り込みを変えたらサービスの選択は外す。ここもページ送りを動かすので、
        // アニメーションを挟まずに切り替える。
        // 絞り込みを変えると選んだものが画面から消えたまま件数だけ残ってしまう。
        // 見えていないものを消すことになるので、切り替えでは編集モードごと畳む
        .onChange(of: filter) { _, _ in
            withoutAnimation {
                selectedService = nil
                exitEditing()
            }
        }
        // まとめて削除は取り消せない。件数を出してもう一度だけ確かめる
        .alert(L.s("edit_delete_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L.s("action_cancel"), role: .cancel) {}
            Button(L.s("action_delete"), role: .destructive, action: deleteSelected)
        } message: {
            Text(L.plural("edit_delete_confirm_message", selectedItems.count))
        }
        .sheet(isPresented: $showCollectionPick) {
            CollectionPickSheet(
                selectedCount: selectedItems.count,
                collections: state.collections,
                allItems: state.items,
                onPick: addSelected(to:)
            )
        }
    }

    private func items(for label: String?, groups: [DomainGroup]) -> [StashItem] {
        guard let label else { return visibleItems }
        return groups.first { $0.label == label }?.items ?? []
    }

    // MARK: - 編集モード

    private func toggle(_ item: StashItem) {
        if selectedIds.contains(item.id) {
            selectedIds.remove(item.id)
        } else {
            selectedIds.insert(item.id)
        }
    }

    private func exitEditing() {
        editing = false
        selectedIds = []
    }

    private func deleteSelected() {
        let count = selectedItems.count
        StashRepository.shared.deleteItems(ids: selectedItems.map(\.id))
        exitEditing()
        toast.show(L.plural("edit_deleted", count))
    }

    private func addSelected(to collection: StashCollection) {
        let count = selectedItems.count
        StashRepository.shared.setCollection(
            ids: selectedItems.map(\.id),
            collectionId: collection.id
        )
        showCollectionPick = false
        // 入れ終わったら選択を残しても次にできることが無いので、編集モードごと畳む
        exitEditing()
        toast.show(L.plural("edit_added_to_collection", count, collection.name))
    }
}

/// 1サービスぶんの一覧。リスト/グリッドの切り替えを内側に閉じ込める
private struct ItemPage: View {
    let items: [StashItem]
    let viewMode: ViewMode
    let filter: HomeFilter
    let editing: Bool
    let selectedIds: Set<String>
    let onItemTap: (StashItem) -> Void
    let onItemLongPress: (StashItem) -> Void
    let onShowGuide: () -> Void
    var highlightItemId: String?

    var body: some View {
        let rows = buildHomeRows(items)

        ScrollView {
            Group {
                if rows.isEmpty {
                    empty
                } else if viewMode == .list {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { row in
                            switch row {
                            case let .link(item):
                                ItemRow(
                                    item: item,
                                    showUnreadDot: false,
                                    selecting: editing,
                                    selected: selectedIds.contains(item.id),
                                    onLongPress: { onItemLongPress(item) }
                                ) { onItemTap(item) }
                                    .spotlightAnchor(.savedItem, active: item.id == highlightItemId)
                            case .ad:
                                NativeAdCard()
                            }
                        }
                    }
                } else {
                    gridBody(rows: rows)
                }
            }
            .padding(.horizontal, screenPadding)
            .padding(.bottom, bottomContentPadding)
        }
        .scrollIndicators(.hidden)
    }

    /// 広告は横幅いっぱい。2列に割ると規定サイズを満たせないので、
    /// リンクの塊と広告を交互に積む
    private func gridBody(rows: [HomeRow]) -> some View {
        LazyVStack(spacing: 11) {
            ForEach(Array(chunks(rows).enumerated()), id: \.offset) { _, chunk in
                switch chunk {
                case let .links(items):
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 11, alignment: .top),
                            GridItem(.flexible(), spacing: 11, alignment: .top),
                        ],
                        spacing: 11
                    ) {
                        ForEach(items) { item in
                            ItemGridCard(
                                item: item,
                                selecting: editing,
                                selected: selectedIds.contains(item.id),
                                onLongPress: { onItemLongPress(item) }
                            ) { onItemTap(item) }
                                .spotlightAnchor(.savedItem, active: item.id == highlightItemId)
                        }
                    }
                case .ad:
                    NativeAdCard()
                }
            }
        }
    }

    private enum Chunk {
        case links([StashItem])
        case ad
    }

    private func chunks(_ rows: [HomeRow]) -> [Chunk] {
        var result: [Chunk] = []
        var buffer: [StashItem] = []
        for row in rows {
            switch row {
            case let .link(item):
                buffer.append(item)
            case .ad:
                if !buffer.isEmpty {
                    result.append(.links(buffer))
                    buffer = []
                }
                result.append(.ad)
            }
        }
        if !buffer.isEmpty { result.append(.links(buffer)) }
        return result
    }

    @ViewBuilder
    private var empty: some View {
        switch filter {
        case .inbox:
            ShareHintCard(onShowGuide: onShowGuide)
        case .favorite:
            EmptyState(icon: Lucide.star, message: L.s("home_empty_favorites"))
        case .archived:
            EmptyState(icon: Lucide.archive, message: L.s("home_empty_archived"))
        }
    }
}

/// ワードマーク・フィルタ・表示切替・サービスチップ
/// 保存件数が上限に近いことの知らせ。
///
/// 上限に当たると共有からの保存が黙って失敗したように見えるので、
/// 手前から残り件数を出しておく。満杯になったら文言を強い方へ差し替える。
private struct LimitBanner: View {
    let remaining: Int

    private var isFull: Bool { remaining <= 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIconView(
                icon: Lucide.triangleAlert,
                size: 16,
                color: isFull ? Palette.accent900 : Palette.accent700
            )
            .padding(.top, 1)
            Text(
                isFull
                    ? L.s("home_limit_reached", StashRepository.maxItems)
                    : L.s("home_limit_near", remaining)
            )
            .font(PokkeType.bodySmall)
            .foregroundStyle(isFull ? Palette.accent900 : Palette.accent800)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Corner.medium, style: .continuous)
                .fill(isFull ? Palette.accent200 : Palette.accent100)
        )
    }
}

private struct HomeHeader: View {
    let state: StashState
    @Binding var filter: HomeFilter
    let groups: [DomainGroup]
    @Binding var selectedService: String?
    let onAddLink: () -> Void

    @ObservedObject private var prefs = AppPrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Wordmark()
                Spacer(minLength: 0)
                // 保存の主導線は他アプリの共有シートなので、ここは控えめな丸ボタンでよい
                CircleIconButton(
                    icon: Lucide.plus,
                    accessibilityLabel: L.s("add_link_title"),
                    action: onAddLink
                )
                .spotlightAnchor(.addLink)
            }

            HStack {
                SegmentedPills {
                    SegmentPill(selected: filter == .inbox) {
                        withoutAnimation { filter = .inbox }
                    } content: {
                        SegmentLabel(
                            text: L.s("filter_unread"),
                            count: HomeFilter.inbox.count(in: state.items),
                            selected: filter == .inbox
                        )
                    }
                    // お気に入りだけ星印にしてある。3つとも文字にすると、
                    // 隣の表示切替と合わせて小さい端末で横に収まらない
                    SegmentPill(selected: filter == .favorite, horizontalPadding: 11) {
                        withoutAnimation { filter = .favorite }
                    } content: {
                        LucideIconView(
                            icon: Lucide.star,
                            size: 15,
                            color: filter == .favorite ? Palette.accent700 : Palette.neutral700
                        )
                        Text("\(HomeFilter.favorite.count(in: state.items))")
                            .font(PokkeType.bodySmall)
                            .foregroundStyle(
                                (filter == .favorite ? Palette.ink : Palette.neutral700).opacity(0.65)
                            )
                    }
                    .accessibilityLabel(L.s("filter_favorite"))
                    SegmentPill(selected: filter == .archived) {
                        withoutAnimation { filter = .archived }
                    } content: {
                        SegmentLabel(
                            text: L.s("filter_archived"),
                            count: HomeFilter.archived.count(in: state.items),
                            selected: filter == .archived
                        )
                    }
                }
                .spotlightAnchor(.filters)
                Spacer(minLength: 8)
                ViewModeToggle()
            }
            .padding(.top, 16)

            if !groups.isEmpty {
                ServiceChips(
                    groups: groups,
                    totalCount: groups.reduce(0) { $0 + $1.items.count },
                    selected: $selectedService
                )
                .padding(.top, 12)
            }
        }
        .padding(.bottom, 12)
    }
}

/// 左上のワードマーク。編集モードでも同じ位置に出したままにする
private struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Pokke")
                .font(PokkeType.display)
                .foregroundStyle(Palette.accent)
            LucideIconView(icon: Lucide.bookmark, size: 18, color: Palette.accent2)
                .padding(.top, 4)
        }
    }
}

/// 編集モードのヘッダー。選んだ件数・全選択と、まとめてできること
/// （コレクションへ追加／削除）を置く。
///
/// 通常時のヘッダーと同じ骨組み（ワードマーク＋右上の丸ボタン → 中段 → 下段）で組んである。
/// 編集中も「今どのアプリのどの画面にいるか」が変わったわけではないので、
/// ロゴまで消すと別画面へ飛ばされたように見える。
///
/// 全選択が効くのは今開いているサービスのページぶんだけ。見えていない
/// ページのリンクまで巻き込むと、押した人の想定と消えるものがずれる。
private struct EditHeader: View {
    let selectedCount: Int
    let pageItems: [StashItem]
    @Binding var selectedIds: Set<String>
    let canAddToCollection: Bool
    let onAddToCollection: () -> Void
    let onDelete: () -> Void
    let onExit: () -> Void

    private var pageIds: Set<String> { Set(pageItems.map(\.id)) }
    private var allSelected: Bool { !pageIds.isEmpty && pageIds.isSubset(of: selectedIds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 通常時の「＋」と同じ場所・同じ形の丸ボタン。中身だけ「編集をやめる」に替える
            HStack(spacing: 8) {
                Wordmark()
                Spacer(minLength: 0)
                CircleIconButton(
                    icon: Lucide.x,
                    accessibilityLabel: L.s("edit_exit"),
                    iconSize: 17,
                    action: onExit
                )
            }

            // 通常時の絞り込みピルと同じ高さにそろえる。段の高さが変わると、
            // 編集モードに入った瞬間に一覧全体が上下にずれる
            HStack(spacing: 10) {
                Text(L.s("edit_selected", selectedCount))
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    if allSelected {
                        selectedIds.subtract(pageIds)
                    } else {
                        selectedIds.formUnion(pageIds)
                    }
                } label: {
                    Text(L.s(allSelected ? "edit_deselect_all" : "edit_select_all"))
                        .font(PokkeType.labelMedium)
                        .foregroundStyle(Palette.accent700)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 40)
            .padding(.top, 16)

            Text(L.s("edit_hint"))
                .font(PokkeType.bodySmall)
                .foregroundStyle(Palette.neutral600)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            // 通常時のサービスチップと同じ位置。取り返しのつく操作を左、
            // 消える操作を右端に置いて、隣同士で押し間違えないようにする
            HStack(spacing: 10) {
                if canAddToCollection {
                    EditActionPill(
                        icon: Lucide.folder,
                        label: L.s("edit_add_to_collection"),
                        enabled: selectedCount > 0,
                        filled: false,
                        action: onAddToCollection
                    )
                }
                Spacer(minLength: 0)
                EditActionPill(
                    icon: Lucide.trash,
                    label: L.s("action_delete"),
                    enabled: selectedCount > 0,
                    filled: true,
                    action: onDelete
                )
            }
            .padding(.top, 12)
        }
        .padding(.bottom, 12)
    }
}

/// 編集モードの操作ボタン。件数が0のときはどれも押せない。
/// [filled] は取り消せない操作（削除）だけ。塗りつぶして他と区別する。
private struct EditActionPill: View {
    let icon: Lucide.Icon
    let label: String
    let enabled: Bool
    let filled: Bool
    let action: () -> Void

    private var contentColor: Color {
        if !enabled { return Palette.neutral600 }
        return filled ? .white : Palette.ink
    }

    private var background: Color {
        if !filled { return Palette.surface }
        return enabled ? Palette.accent800 : Palette.neutral300
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                LucideIconView(icon: icon, size: 15, color: contentColor)
                Text(label)
                    .font(PokkeType.labelMedium)
                    .foregroundStyle(contentColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(surface)
            .overlay(
                Capsule().stroke(filled ? Color.clear : Palette.hairline, lineWidth: 1.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.pressScale(0.95))
        .disabled(!enabled)
    }

    /// 影が付くのは塗りのボタンだけ。押せない間は浮かせない
    @ViewBuilder
    private var surface: some View {
        if filled, enabled {
            Capsule().fill(background).softShadow(.sm)
        } else {
            Capsule().fill(background)
        }
    }
}

/// 「未読 12」のように、ラベルと件数で文字の濃さを変える
private struct SegmentLabel: View {
    let text: String
    let count: Int
    let selected: Bool

    var body: some View {
        let color = selected ? Palette.ink : Palette.neutral700
        Text(text)
            .font(PokkeType.labelMedium)
            .foregroundStyle(color)
            .lineLimit(1)
        Text("\(count)")
            .font(PokkeType.bodySmall)
            .foregroundStyle(color.opacity(0.65))
    }
}

/// サービスごとの横スクロールチップ。
/// 見出しを挟む方式だと件数が増えたとき目的のサービスまで延々スクロールが必要になるため、
/// チップで絞り込む形にしている。
private struct ServiceChips: View {
    let groups: [DomainGroup]
    let totalCount: Int
    @Binding var selected: String?

    private let allChipId = "__all__"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ServiceChip(
                        label: L.s("service_tab_all"),
                        count: totalCount,
                        selected: selected == nil
                    ) {
                        selected = nil
                    }
                    .id(allChipId)

                    ForEach(groups) { group in
                        ServiceChip(
                            label: group.isOther ? L.s("service_tab_other") : group.label,
                            count: group.items.count,
                            selected: selected == group.label,
                            action: { selected = group.label }
                        ) {
                            chipIcon(for: group)
                        }
                        .id(group.label)
                    }
                }
                // チップ列だけは画面端まで流したいので、一覧の左右余白を打ち消す
                .padding(.horizontal, screenPadding)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -screenPadding)
            // スワイプでページが変わったとき、対応するチップが画面外だと
            // 今どのサービスを見ているのか分からなくなる
            .onChange(of: selected) { _, value in
                withAnimation { proxy.scrollTo(value ?? allChipId, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func chipIcon(for group: DomainGroup) -> some View {
        let tint: Color = selected == group.label ? Palette.surface : Palette.neutral700
        if group.isOther {
            LucideIconView(icon: Lucide.link, size: 14, color: tint)
        } else {
            ServiceLogo(domain: group.domain, label: group.label, size: 14, tint: tint)
        }
    }
}
