import Foundation
import Observation

enum RootTab: Hashable {
    case search
    case bookmarks
    case settings
}

@Observable
final class AppCoordinator {
    var selectedTab: RootTab = .search
    var searchPath: [SearchRoute] = []
    var bookmarksPath: [BookmarksRoute] = []
    var settingsPath: [SettingsRoute] = []

    func popToRoot() {
        switch selectedTab {
        case .search: searchPath = []
        case .bookmarks: bookmarksPath = []
        case .settings: settingsPath = []
        }
    }

    func popToRoot(of tab: RootTab) {
        switch tab {
        case .search: searchPath = []
        case .bookmarks: bookmarksPath = []
        case .settings: settingsPath = []
        }
    }
}
