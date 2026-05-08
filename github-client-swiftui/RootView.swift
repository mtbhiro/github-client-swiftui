import SwiftUI

enum RootTab: Hashable {
    case search
    case bookmarks
    case settings
}

struct RootView: View {
    @State private var selection: RootTab = .search

    var body: some View {
        TabView(selection: $selection) {
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
        .environment(BookmarkStore(items: []))
}
