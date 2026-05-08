import SwiftUI

@main
struct github_client_swiftuiApp: App {
    @State private var bookmarkStore = BookmarkStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(bookmarkStore)
        }
    }
}
