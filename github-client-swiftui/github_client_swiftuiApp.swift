import SwiftUI

@main
struct github_client_swiftuiApp: App {
    @State private var bookmarkStore = BookmarkStore()
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(bookmarkStore)
                .environment(coordinator)
        }
    }
}
