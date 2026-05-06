import SwiftUI

enum RootTab: Hashable {
    case search
    case myPage
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

            MyPageView()
                .tabItem {
                    Label("マイページ", systemImage: "person.crop.circle")
                }
                .tag(RootTab.myPage)

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
}
