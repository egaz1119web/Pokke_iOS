import SwiftUI

private let sampleLinks = [
    "https://developer.apple.com/xcode/swiftui/",
    "https://ja.wikipedia.org/wiki/%E8%AA%AD%E6%9B%B8",
    "https://www.aozora.gr.jp/",
    "https://blog.google/",
]

private enum Tab: Int, CaseIterable {
    case home, collections, search, settings

    var titleKey: String {
        switch self {
        case .home: return "tab_home"
        case .collections: return "tab_collections"
        case .search: return "tab_search"
        case .settings: return "tab_settings"
        }
    }

    /// Androidは絵文字アイコンだが、iOSのタブバーはSF Symbolsが標準の見え方なのでそちらに合わせる
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .collections: return "books.vertical"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @ObservedObject private var repository = StashRepository.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: Tab = .home
    @State private var showAdd = false
    @State private var showCreateCollection = false
    @State private var detailId: String?

    private var state: StashState { repository.state }

    private var detailItem: StashItem? {
        detailId.flatMap { id in state.items.first { $0.id == id } }
    }

    var body: some View {
        TabView(selection: $tab) {
            screen(.home) {
                HomeScreen(
                    state: state,
                    onItemTap: { detailId = $0.id },
                    onAddSamples: { sampleLinks.forEach { StashRepository.shared.addLink($0) } }
                )
            }
            screen(.collections) {
                CollectionsScreen(
                    state: state,
                    onItemTap: { detailId = $0.id },
                    showCreate: $showCreateCollection
                )
            }
            screen(.search) {
                SearchScreen(state: state, onItemTap: { detailId = $0.id })
            }
            screen(.settings) {
                SettingsScreen()
            }
        }
        .tint(Palette.primary)
        // Android版が lightColorScheme 固定なので、見た目を揃えるためライトに固定する
        .preferredColorScheme(.light)
        .sheet(isPresented: $showAdd) {
            AddLinkSheet { url in
                StashRepository.shared.addLink(url) != nil
            }
        }
        .sheet(item: Binding(
            get: { detailItem },
            set: { if $0 == nil { detailId = nil } }
        )) { item in
            DetailSheet(item: item, collections: state.collections)
        }
        .onChange(of: scenePhase) { _, phase in
            // 共有拡張が別プロセスで書き足した分をここで拾う
            if phase == .active { repository.reloadFromDisk() }
        }
    }

    /// タブ1枚分。「＋」ボタンはホーム/コレクションでだけ出す（Android版のFABと同じ）
    private func screen<Content: View>(
        _ item: Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Palette.appBackground.ignoresSafeArea()
            content()
            if item == .home || item == .collections {
                AddButton { showAdd = true }
            }
        }
        .tabItem { Label(L.s(item.titleKey), systemImage: item.systemImage) }
        .tag(item)
    }
}
