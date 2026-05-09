import Foundation

enum SearchRoute: Hashable {
    case repositoryDetail(GitHubRepoFullName)
    case issueList(GitHubRepoFullName)
    case issueDetail(GitHubRepoFullName, number: Int)
}

enum BookmarksRoute: Hashable {
    case repositoryDetail(GitHubRepoFullName)
    case issueList(GitHubRepoFullName)
    case issueDetail(GitHubRepoFullName, number: Int)
}

enum SettingsRoute: Hashable {}
