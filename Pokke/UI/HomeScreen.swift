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
    @State private var filter: HomeFilter = .inbox
    /// 選択中サービスのラベル。nil は「すべて」。スワイプでもチップでも同じ状態を見る
    @State private var selectedService: String?

    private var visibleItems: [StashItem] {
        state.items
            .filter(filter.matches)
            .sorted { $0.savedAt > $1.savedAt }
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
            HomeHeader(
                state: state,
                filter: $filter,
                groups: groups,
                selectedService: $selectedService,
                onAddLink: onAddLink
            )
            .padding(.horizontal, screenPadding)
            .padding(.top, 18)

            // 上限に当たってから知るのでは遅い。手前から残りを見せておく
            let remaining = StashRepository.maxItems - state.items.count
            if remaining <= StashRepository.limitWarningRemaining {
                LimitBanner(remaining: remaining)
                    .padding(.horizontal, screenPadding)
                    .padding(.top, 12)
            }

            // 寝かせたままのリンクがたまってきたら整理をすすめる。
            // 上限の知らせと同時に出ると押し付けがましいので、そちらを優先する
            if remaining > StashRepository.limitWarningRemaining, showsCleanupNotice {
                CleanupBanner(count: staleCount, onOpen: onCleanup) {
                    prefs.snoozeCleanupNotice()
                }
                .padding(.horizontal, screenPadding)
                .padding(.top, 12)
            }

            TabView(selection: $selectedService) {
                ForEach(pages, id: \.self) { label in
                    ItemPage(
                        items: items(for: label, groups: groups),
                        viewMode: prefs.viewMode,
                        filter: filter,
                        onItemTap: onItemTap,
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
        .onChange(of: filter) { _, _ in selectedService = nil }
    }

    private func items(for label: String?, groups: [DomainGroup]) -> [StashItem] {
        guard let label else { return visibleItems }
        return groups.first { $0.label == label }?.items ?? []
    }
}

/// 1サービスぶんの一覧。リスト/グリッドの切り替えを内側に閉じ込める
private struct ItemPage: View {
    let items: [StashItem]
    let viewMode: ViewMode
    let filter: HomeFilter
    let onItemTap: (StashItem) -> Void
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
                                ItemRow(item: item, showUnreadDot: false) { onItemTap(item) }
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
                            ItemGridCard(item: item) { onItemTap(item) }
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
                Text("Pokke")
                    .font(PokkeType.display)
                    .foregroundStyle(Palette.accent)
                LucideIconView(icon: Lucide.bookmark, size: 18, color: Palette.accent2)
                    .padding(.top, 4)
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
                        filter = .inbox
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
                        filter = .favorite
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
                        filter = .archived
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
                SegmentedPills {
                    ViewModePill(
                        icon: Lucide.listView,
                        label: L.s("view_list"),
                        selected: prefs.viewMode == .list
                    ) { prefs.setViewMode(.list) }
                    ViewModePill(
                        icon: Lucide.grid,
                        label: L.s("view_grid"),
                        selected: prefs.viewMode == .grid
                    ) { prefs.setViewMode(.grid) }
                }
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

private struct ViewModePill: View {
    let icon: Lucide.Icon
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        SegmentPill(selected: selected, horizontalPadding: 9, width: 36, action: action) {
            LucideIconView(icon: icon, size: 17, color: selected ? Palette.ink : Palette.neutral700)
                .accessibilityLabel(label)
        }
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
