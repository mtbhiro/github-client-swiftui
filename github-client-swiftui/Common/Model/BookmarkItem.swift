import Foundation

enum BookmarkItem: Sendable, Codable, Hashable, Identifiable {
    case repository(RepositoryBookmark)
    case issue(IssueBookmark)

    var id: String {
        switch self {
        case let .repository(repo):
            "repo:\(repo.ownerLogin)/\(repo.repositoryName)"
        case let .issue(issue):
            "issue:\(issue.ownerLogin)/\(issue.repositoryName)#\(issue.number)"
        }
    }

    var isRepository: Bool {
        if case .repository = self { return true }
        return false
    }

    var isIssue: Bool {
        if case .issue = self { return true }
        return false
    }
}

struct RepositoryBookmark: Sendable, Codable, Hashable {
    let ownerLogin: String
    let repositoryName: String
    let fullName: String
    let description: String?
    let stargazersCount: Int
    let language: String?
    let createdAt: Date
}

struct IssueBookmark: Sendable, Codable, Hashable {
    let ownerLogin: String
    let repositoryName: String
    let number: Int
    let title: String
    let state: IssueState
    let isPullRequest: Bool
    let createdAt: Date
}
