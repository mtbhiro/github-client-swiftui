import Foundation

enum SearchRoute: Hashable {
    case repositoryDetail(ownerLogin: String, repositoryName: String)
    case issueList(ownerLogin: String, repositoryName: String)
    case issueDetail(ownerLogin: String, repositoryName: String, number: Int)
}

enum BookmarksRoute: Hashable {
    case repositoryDetail(ownerLogin: String, repositoryName: String)
    case issueList(ownerLogin: String, repositoryName: String)
    case issueDetail(ownerLogin: String, repositoryName: String, number: Int)
}

enum SettingsRoute: Hashable {}
