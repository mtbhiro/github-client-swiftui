import Foundation

enum ContentRoute: Hashable {
    case repositoryDetail(GitHubRepoFullName)
    case issueList(GitHubRepoFullName)
    case issueDetail(GitHubRepoFullName, number: Int)
}

enum SettingsRoute: Hashable {
    case deviceFlow
}
