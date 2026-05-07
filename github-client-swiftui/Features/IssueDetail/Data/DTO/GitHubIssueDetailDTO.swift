import Foundation

nonisolated struct GitHubIssueDetailDTO: Decodable, Sendable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String
    let user: GitHubUserDTO
    let labels: [GitHubLabelDTO]
    let comments: Int
    let htmlUrl: String
    let createdAt: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case body
        case state
        case user
        case labels
        case comments
        case htmlUrl = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> GitHubIssueDetail {
        let formatter = ISO8601DateFormatter()
        return GitHubIssueDetail(
            id: id,
            number: number,
            title: title,
            body: body,
            state: IssueState(rawValue: state) ?? .open,
            user: user.toDomain(),
            labels: labels.map { $0.toDomain() },
            commentsCount: comments,
            htmlUrl: URL(string: htmlUrl)!,
            createdAt: formatter.date(from: createdAt) ?? .distantPast,
            updatedAt: formatter.date(from: updatedAt) ?? .distantPast
        )
    }
}

nonisolated struct GitHubIssueCommentDTO: Decodable, Sendable {
    let id: Int
    let user: GitHubUserDTO
    let body: String
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case createdAt = "created_at"
    }

    func toDomain() -> GitHubIssueComment {
        let formatter = ISO8601DateFormatter()
        return GitHubIssueComment(
            id: id,
            user: user.toDomain(),
            body: body,
            createdAt: formatter.date(from: createdAt) ?? .distantPast
        )
    }
}
