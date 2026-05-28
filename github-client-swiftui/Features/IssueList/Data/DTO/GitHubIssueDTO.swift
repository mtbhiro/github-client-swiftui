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

    func toDomain() throws -> GitHubIssue {
        guard let parsedCreatedAt = DateFormatters.iso8601.date(from: createdAt) else {
            throw DTOMappingError.invalidDate(field: "createdAt", value: createdAt)
        }
        return GitHubIssue(
            id: id,
            number: number,
            title: title,
            state: IssueState(rawValue: state) ?? .open,
            user: try user.toDomain(),
            labels: labels.map { $0.toDomain() },
            commentsCount: comments,
            createdAt: parsedCreatedAt,
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

    func toDomain() throws -> GitHubUser {
        guard let userHtmlUrl = URL(string: htmlUrl) else {
            throw DTOMappingError.invalidURL(field: "user.htmlUrl", value: htmlUrl)
        }
        return GitHubUser(
            login: login,
            id: id,
            avatarUrl: URL(string: avatarUrl),
            htmlUrl: userHtmlUrl
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
