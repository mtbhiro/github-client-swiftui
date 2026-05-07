import Foundation

nonisolated struct GitHubIssueDTO: Decodable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let state: String
    let user: GitHubUserDTO
    let labels: [GitHubLabelDTO]
    let comments: Int
    let createdAt: String
    let pullRequest: PullRequestRefDTO?

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case state
        case user
        case labels
        case comments
        case createdAt = "created_at"
        case pullRequest = "pull_request"
    }

    func toDomain() -> GitHubIssue {
        let formatter = ISO8601DateFormatter()
        return GitHubIssue(
            id: id,
            number: number,
            title: title,
            state: IssueState(rawValue: state) ?? .open,
            user: user.toDomain(),
            labels: labels.map { $0.toDomain() },
            commentsCount: comments,
            createdAt: formatter.date(from: createdAt) ?? .distantPast,
            isPullRequest: pullRequest != nil
        )
    }
}

nonisolated struct PullRequestRefDTO: Decodable, Sendable {
    let url: String?
}

nonisolated struct GitHubUserDTO: Decodable, Sendable {
    let login: String
    let id: Int
    let avatarUrl: String
    let htmlUrl: String

    private enum CodingKeys: String, CodingKey {
        case login
        case id
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
    }

    func toDomain() -> GitHubUser {
        GitHubUser(
            login: login,
            id: id,
            avatarUrl: URL(string: avatarUrl),
            htmlUrl: URL(string: htmlUrl)!
        )
    }
}

nonisolated struct GitHubLabelDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let color: String

    func toDomain() -> GitHubLabel {
        GitHubLabel(
            id: id,
            name: name,
            color: color
        )
    }
}
