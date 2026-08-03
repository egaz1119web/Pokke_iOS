import StoreKit
import SwiftUI

/// 画面の左右余白。全画面で共通の18pt
let screenPadding: CGFloat = 18

/// ボトムナビの高さ。一覧の下端がナビに隠れないよう余白の計算にも使う
private let navBarHeight: CGFloat = 68

/// 一覧の下端に置く余白。
/// ナビはコンテンツの上に浮いているので、その高さ＋少しの余白ぶん空ける
/// （ホームインジケータぶんはScrollView自身のセーフエリアが持つ）
let bottomContentPadding = navBarHeight + 16

private enum RootTab: Int, CaseIterable, Identifiable {
    case home, collections, search, settings

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .home: return "tab_home"
        case .collections: return "tab_collections"
        case .search: return "tab_search"
        case .settings: return "tab_settings"
        }
    }

    var icon: Lucide.Icon {
        switch self {
        case .home: return Lucide.house
        case .collections: return Lucide.folder
        case .search: return Lucide.search
        case .settings: return Lucide.settings
        }
    }
}

struct RootView: View {
    @ObservedObject private var repository = StashRepository.shared
    @ObservedObject private var prefs = AppPrefs.shared
    @ObservedObject private var notifications = NotificationRouter.shared
    @StateObject private var toast = ToastController()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

    @State private var tab: RootTab = .home
    @State private var showAdd = false
    @State private var showCleanup = false
    @State private var detailId: String?
    @State private var openedCollectionId: String?
    /// 初回起動時は共有からの保存方法を案内する
    @State private var showGuide = false
    /// ホームに重ねるスポットライト案内の現在のコマ。出していないときは nil
    @State private var tourStep: Int?
    /// スポットライトで指す、練習で保存できた1件
    @State private var tourItemId: String?

    private var state: StashState { repository.state }

    private var detailItem: StashItem? {
        detailId.flatMap { id in state.items.first { $0.id == id } }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomNav(selected: tab) { next in
                // 別のタブへ移ったらコレクション詳細のような下位の画面は畳む。
                // 戻ってきたときに前回の続きが出ていると、今どこにいるのか分からなくなる
                if next != tab { openedCollectionId = nil }
                tab = next
            }

            ToastHost(controller: toast)
        }
        .overlayPreferenceValue(SpotlightAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let tourStep {
                    SpotlightOverlay(
                        steps: SpotlightStep.afterFirstSave,
                        index: tourStep,
                        hole: holeRect(step: tourStep, anchors: anchors, proxy: proxy),
                        size: proxy.size,
                        onNext: { advanceTour() },
                        onClose: { endTour() }
                    )
                    .transition(.opacity)
                }
            }
            // 案内はステータスバーやホームインジケータの帯まで覆う。
            // 穴の座標もこの全画面の枠を基準に解く
            .ignoresSafeArea()
            .allowsHitTesting(tourStep != nil)
        }
        .environmentObject(toast)
        // Android版が lightColorScheme 固定なので、見た目を揃えるためライトに固定する
        .preferredColorScheme(.light)
        // 案内は重ねるのではなく画面を占有させる。共有シートを実際に開いて練習する
        // 手順があり、後ろの一覧が透けているとどこを見ればよいのか分からなくなる
        .fullScreenCover(isPresented: $showGuide) {
            OnboardingFlow { savedItem in
                showGuide = false
                AppPrefs.shared.markOnboarded()
                if let savedItem { startTour(savedItemId: savedItem.id) }
            }
        }
        .sheet(isPresented: $showAdd) {
            SaveLinkSheet { url in
                let result = StashRepository.shared.addLink(url)
                if case .saved = result { toast.show(L.s("toast_saved")) }
                return result
            }
        }
        .sheet(isPresented: $showCleanup) {
            // 開いた時点の一覧で固定する。開いている間に共有拡張やクラウド同期で
            // 中身が入れ替わると、チェックした行と消える行がずれる
            CleanupSheet(items: OldItems.stale(items: state.items, now: nowMillis()))
                .environmentObject(toast)
        }
        .sheet(item: Binding(
            get: { detailItem },
            set: { if $0 == nil { detailId = nil } }
        )) { item in
            DetailSheet(item: item, collections: state.collections, allItems: state.items)
                .environmentObject(toast)
        }
        .onAppear {
            if AppPrefs.shared.needsOnboarding { showGuide = true }
            // 通知の予約はOS側に残っているが、消えたリンクのぶんが混ざっていることがある
            syncReminders()
            // 通知から起動した場合、画面が乗る前に届いているので拾いに行く
            openFromNotification(notifications.openItemId)
        }
        .onChange(of: scenePhase) { _, phase in
            // 共有拡張が別プロセスで書き足した分をここで拾う
            if phase == .active {
                repository.reloadFromDisk()
                // 読み直した後に見るので、共有シート経由で貯めた分も件数に入る
                maybeRequestReview()
                syncReminders()
            }
        }
        // 予約は保存内容の写しなので、リマインダーが動いたら必ず取り直す。
        // 自分で設定したときだけでなく、クラウド同期で別端末から入ってきた分や
        // まとめて削除した分もここを通る
        .onChange(of: reminderSignature) { _, _ in syncReminders() }
        // 通知から起動したときは、そのリンクの詳細を開く
        .onChange(of: notifications.openItemId) { _, id in openFromNotification(id) }
    }

    // MARK: - リマインダー

    /// 予約に関わる部分だけを取り出した目印。
    /// `state` 全体を見張るとタイトルの取得やタグ付けでも取り直しが走ってしまう
    private var reminderSignature: [String] {
        state.items.compactMap { item in
            item.remindAt.map { "\(item.id):\($0)" }
        }
    }

    private func syncReminders() {
        Task { await ReminderScheduler.shared.sync(items: state.items) }
    }

    /// 通知から来た1件を開く。すでに消えている場合は何もしない
    private func openFromNotification(_ id: String?) {
        guard let id, state.items.contains(where: { $0.id == id }) else { return }
        showGuide = false
        showCleanup = false
        detailId = id
        notifications.openItemId = nil
    }

    // MARK: - ホームのスポットライト案内

    /// 初回案内で1件目を保存できた直後に始める。
    ///
    /// 案内の中で「保存できました」と見せるより、本物のホームに並んだところを
    /// 指した方が早い。ついでに残りの使い方もその場の実物で説明する。
    private func startTour(savedItemId: String) {
        tab = .home
        openedCollectionId = nil
        tourItemId = savedItemId
        Task {
            // 案内の画面が閉じ切り、ホームの一覧が並ぶまで待つ。
            // 先に出すと穴を開ける先がまだ無く、いきなり暗転だけが見える
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.3)) { tourStep = 0 }
        }
    }

    private func advanceTour() {
        guard let current = tourStep else { return }
        let next = current + 1
        if next < SpotlightStep.afterFirstSave.count {
            withAnimation(.easeOut(duration: 0.3)) { tourStep = next }
        } else {
            endTour()
        }
    }

    private func endTour() {
        withAnimation(.easeOut(duration: 0.25)) { tourStep = nil }
        tourItemId = nil
    }

    /// 今のコマが指す枠。畳まれていて画面に無い物は指さない（穴だけが宙に浮く）
    private func holeRect(
        step: Int,
        anchors: [SpotlightTarget: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> CGRect? {
        guard let anchor = anchors[SpotlightStep.afterFirstSave[step].target] else { return nil }
        let inset = SpotlightStep.afterFirstSave[step].inset
        let rect = proxy[anchor]
        guard rect.midY > 0, rect.midY < proxy.size.height else { return nil }
        return rect.insetBy(dx: -inset, dy: -inset)
    }

    /// 使い込んでくれている人にだけ、Apple純正の星評価ダイアログを出す。
    ///
    /// 起動直後に重ねると操作を遮るので、画面が落ち着くまで少し待つ。
    /// 初回案内やスポットライトが出ている間は譲る
    /// （条件的にほぼ重ならないが、重なると案内が隠れる）
    private func maybeRequestReview() {
        guard !showGuide, tourStep == nil else { return }
        guard ReviewPrompt.shouldRequest(
            itemCount: state.items.count,
            firstLaunchAt: prefs.firstLaunchAt,
            alreadyRequested: prefs.reviewRequested
        ) else { return }

        // 出したこと自体は即座に記録する。ダイアログはOSの判断で出ないこともあり、
        // 記録を遅らせると起動のたびに何度も声をかけることになる
        prefs.markReviewRequested()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            HomeScreen(
                state: state,
                onItemTap: { detailId = $0.id },
                onShowGuide: { showGuide = true },
                onAddLink: { showAdd = true },
                onCleanup: { showCleanup = true },
                highlightItemId: tourItemId
            )
        case .collections:
            CollectionsScreen(
                state: state,
                openedCollectionId: $openedCollectionId,
                onItemTap: { detailId = $0.id },
                onBrowseLinks: {
                    openedCollectionId = nil
                    tab = .home
                }
            )
        case .search:
            SearchScreen(state: state, onItemTap: { detailId = $0.id })
        case .settings:
            SettingsScreen(
                onShowGuide: { showGuide = true },
                onCleanup: { showCleanup = true }
            )
        }
    }
}

/// ボトムナビ。コンテンツの上に浮かせているので、地は白の半透明にして
/// 下に何かあることが分かるようにしている。
private struct BottomNav: View {
    let selected: RootTab
    let onSelect: (RootTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
            HStack(spacing: 4) {
                ForEach(RootTab.allCases) { item in
                    NavItem(
                        icon: item.icon,
                        label: L.s(item.titleKey),
                        selected: selected == item
                    ) { onSelect(item) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .spotlightAnchor(.nav)
        }
        // ホームインジケータの帯まで地を伸ばす。ここが透けると下の文字と重なって読めない
        .background {
            Palette.surface.opacity(0.92).ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct NavItem: View {
    let icon: Lucide.Icon
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                LucideIconView(icon: icon, size: 21, color: color)
                Text(label)
                    .font(PokkeType.labelSmall)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 7)
            .padding(.bottom, 5)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Palette.accent100 : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var color: Color { selected ? Palette.accent800 : Palette.neutral600 }
}
