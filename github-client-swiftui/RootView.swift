import SwiftUI

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.githubRepository) private var repository
    // PRD repository-search-cache.md AC-6.3: 検索画面のライフサイクルとは独立にキャッシュを保持する。
    // RootView は TabView のホストとしてアプリ起動中は破棄されない前提なので、@State の identity が
    // RepositorySearchView の pop/再構築をまたいで同じインスタンスを維持する。
    @State private var searchCache = RepositorySearchCache()

    var body: some View {
        @Bindable var coordinator = coordinator
        TabView(selection: $coordinator.selectedTab) {
            RepositorySearchView(cache: searchCache, repository: repository)
                .tabItem {
                    Label("検索", systemImage: "magnifyingglass")
                }
                .tag(RootTab.search)

            BookmarkListView()
                .tabItem {
                    Label("ブックマーク", systemImage: "bookmark")
                }
                .tag(RootTab.bookmarks)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .onOpenURL { url in
            coordinator.handle(deepLink: url)
        }
    }
}

#Preview {
    RootView()
        .environment(AppCoordinator())
        .environment(BookmarkStore(items: []))
}
