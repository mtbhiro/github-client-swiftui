import SwiftUI

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        TabView(selection: $coordinator.selectedTab) {
            RepositorySearchView()
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
    }
}

#Preview {
    RootView()
        .environment(AppCoordinator())
        .environment(BookmarkStore(items: []))
}
