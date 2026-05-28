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

    func toDomain() throws -> GitHubIssueDetail {
        let formatter = ISO8601DateFormatter()
        guard let issueHtmlUrl = URL(string: htmlUrl) else {
            throw DTOMappingError.invalidURL(field: "htmlUrl", value: htmlUrl)
        }
        guard let parsedCreatedAt = formatter.date(from: createdAt) else {
            throw DTOMappingError.invalidDate(field: "createdAt", value: createdAt)
        }
        guard let parsedUpdatedAt = formatter.date(from: updatedAt) else {
            throw DTOMappingError.invalidDate(field: "updatedAt", value: updatedAt)
        }
        return GitHubIssueDetail(
            id: id,
            number: number,
            title: title,
            body: body,
            state: IssueState(rawValue: state) ?? .open,
            user: try user.toDomain(),
            labels: labels.map { $0.toDomain() },
            commentsCount: comments,
            htmlUrl: issueHtmlUrl,
            createdAt: parsedCreatedAt,
            updatedAt: parsedUpdatedAt
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

    func toDomain() throws -> GitHubIssueComment {
        let formatter = ISO8601DateFormatter()
        guard let parsedCreatedAt = formatter.date(from: createdAt) else {
            throw DTOMappingError.invalidDate(field: "createdAt", value: createdAt)
        }
        return GitHubIssueComment(
            id: id,
            user: try user.toDomain(),
            body: body,
            createdAt: parsedCreatedAt
        )
    }
}
