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

/// ホーム上部の絞り込み。未読とアーカイブは表裏で、どちらか一方しか選べない。
///
/// **お気に入りはここに入れない**。「残したい」と「読み終えた」は両立するので、
/// 同じ3択に混ぜると「未読のお気に入り」が見られなくなる。
/// 星は別の軸（`HomeScreen` の favoriteOnly）として重ねがけする
private enum HomeFilter: CaseIterable {
    case inbox, archived

    func matches(_ item: StashItem) -> Bool {
        switch self {
        case .inbox: return !item.archived
        case .archived: return item.archived
        }
    }

    /// ピルに出す件数。「未読」だけは並ぶ件数（未アーカイブ全部）ではなく、
    /// まだ開いていない数を出す — 知りたいのは残りの量なので
    func count(in items: [StashItem]) -> Int {
        switch self {
        case .inbox: return items.filter(\.unread).count
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
    /// 星は未読/アーカイブとは別の軸。選んだタブの中をさらに絞る
    @State private var favoriteOnly = false
    /// 選択中サービスのラベル。nil は「すべて」。スワイプでもチップでも同じ状態を見る
    @State private var selectedService: String?

    /// 長押しで入る編集モード。まとめて選んで一度に片付けるためだけの状態
    @State private var editing = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var showCollectionPick = false

    private var visibleItems: [StashItem] {
        state.items
            .filter { filter.matches($0) && (!favoriteOnly || $0.favorite) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// 消えたリンク（他端末との同期など）が選択に残らないようにする。
    /// 並びは一覧と同じ新しい順。共有の文面がこの順で並ぶので、画面と食い違うと読みにくい
    private var selectedItems: [StashItem] {
        visibleItems.filter { selectedIds.contains($0.id) }
    }

    /// 声をかける根拠になる件数。未アーカイブぶんだけを数えるので、
    /// 実際に整理シートへ並ぶ件数（アーカイブ済みを含む）とはずれる。
    /// 声をかける理由は「読まないまま積まれている」ことなので、こちらで判断する
    private var noticeCount: Int {
        OldItems.noticeCount(items: state.items, now: nowMillis())
    }

    private var showsCleanupNotice: Bool {
        guard prefs.cleanupNoticeEnabled else { return false }
        return OldItems.showsNotice(
            staleCount: noticeCount,
            totalCount: state.items.count,
            snoozedAt: prefs.cleanupSnoozedAt,
            dismissCount: prefs.cleanupDismissCount,
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
                        // 共有は編集モードを畳まない。共有シートを閉じただけなのか送ったのかは
                        // こちらから分からず、送らずに戻った人の選択まで消えてしまう。
                        // 送り先を変えてもう一度、もそのまま続けられる
                        onShare: { shareLinks(selectedItems) },
                        onDelete: { showDeleteConfirm = true },
                        onExit: exitEditing
                    )
                } else {
                    HomeHeader(
                        state: state,
                        filter: $filter,
                        favoriteOnly: $favoriteOnly,
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
                CleanupBanner(count: noticeCount, onOpen: onCleanup) {
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
                        favoriteOnly: favoriteOnly,
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
        // 見えていないものを消すことになるので、切り替えでは編集モードごと畳む。
        // 星の絞り込みも同じく画面から行を減らすので、まとめて見張る
        .onChange(of: filter) { _, _ in
            withoutAnimation {
                selectedService = nil
                exitEditing()
            }
        }
        .onChange(of: favoriteOnly) { _, _ in
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
    let favoriteOnly: Bool
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

    /// 星で絞った結果の空は、保存が無いのではなく印が無いだけ。
    /// ここで保存のしかたを案内しても的外れになる
    @ViewBuilder
    private var empty: some View {
        if favoriteOnly {
            EmptyState(icon: Lucide.star, message: L.s("home_empty_favorites"))
        } else if filter == .archived {
            EmptyState(icon: Lucide.archive, message: L.s("home_empty_archived"))
        } else {
            ShareHintCard(onShowGuide: onShowGuide)
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
    @Binding var favoriteOnly: Bool
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
                // 星は別の軸なので、上の囲みの外に出して重ねがけだと分かるようにする。
                // 中に並べると「未読・アーカイブ・お気に入り」の3択に見えてしまう
                FavoriteFilterPill(
                    enabled: favoriteOnly,
                    // 今のタブの中で何件に絞れるかを出す。全体のお気に入り数を出すと、
                    // アーカイブ側にあるぶんまで数えて、押しても件数が合わない
                    count: state.items.filter { filter.matches($0) && $0.favorite }.count
                ) {
                    withoutAnimation { favoriteOnly.toggle() }
                }
                .padding(.leading, 8)
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

/// お気に入りの絞り込み。未読／アーカイブの選択に重ねて効く。
///
/// 左右の絞り込み・表示切替と同じ高さ（`SegmentedPills` の34ptピル＋3ptの内側余白）で
/// 並べつつ、囲みの外に単独で置いてある。入っているときだけ色が付くので、
/// 絞り込みが効いたまま忘れられることもない。
/// 役割がタブではなく入切なので、読み上げにもトグルとして渡す
private struct FavoriteFilterPill: View {
    let enabled: Bool
    let count: Int
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                LucideIconView(
                    icon: Lucide.star,
                    size: 15,
                    color: enabled ? Palette.accent700 : Palette.neutral700
                )
                Text("\(count)")
                    .font(PokkeType.bodySmall)
                    .foregroundStyle((enabled ? Palette.ink : Palette.neutral700).opacity(0.65))
            }
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(Capsule().fill(enabled ? Palette.accent100 : Color.clear))
            .overlay(
                Capsule().stroke(enabled ? Palette.accent : Palette.hairline, lineWidth: 1.5)
            )
            .contentShape(Capsule())
            // 選択の見た目は押した瞬間に入れ替える（[SegmentPill] と同じ理由）
            .transaction { $0.animation = nil }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.s("filter_favorite"))
        .accessibilityAddTraits(enabled ? [.isSelected] : [])
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
/// （コレクションへ追加／共有／削除）を置く。
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
    let onShare: () -> Void
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
                    // 3つ並ぶと横幅がぎりぎりになる。まず余白（Spacer）が詰まり、
                    // それでも足りなければいちばん長いこのラベルから譲る。
                    // 優先度を上げた共有と削除は最後まで欠けない
                    .layoutPriority(1)
                }
                EditActionPill(
                    icon: Lucide.share,
                    label: L.s("edit_share"),
                    enabled: selectedCount > 0,
                    filled: false,
                    action: onShare
                )
                .layoutPriority(2)
                Spacer(minLength: 0)
                EditActionPill(
                    icon: Lucide.trash,
                    label: L.s("action_delete"),
                    enabled: selectedCount > 0,
                    filled: true,
                    action: onDelete
                )
                .layoutPriority(2)
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
