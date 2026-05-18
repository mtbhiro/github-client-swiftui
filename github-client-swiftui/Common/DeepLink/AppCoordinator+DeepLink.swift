import Foundation

extension AppCoordinator {
    // PRD §10 将来課題: Universal Links 拡張時はここに `https://...` 経路の解決も載せる前提。
    // 現状は `DeepLink.parse` が `githubclient` 以外を弾く責務を持つため、ここでは早期 return に依存している。
    func handle(deepLink url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        selectedTab = .search
        searchPath = link.searchPath
    }
}
