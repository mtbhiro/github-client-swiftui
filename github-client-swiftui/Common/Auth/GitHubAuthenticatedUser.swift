import Foundation

nonisolated struct GitHubAuthenticatedUser: Sendable, Equatable, Codable {
    let login: String
    let name: String?
    let avatarURL: URL?
}

nonisolated struct GitHubAuthenticatedUserDTO: Decodable, Sendable {
    let login: String
    let id: Int
    let avatarURL: URL?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case login
        case id
        case avatarURL = "avatar_url"
        case name
    }

    func toDomain() -> GitHubAuthenticatedUser {
        GitHubAuthenticatedUser(login: login, name: name, avatarURL: avatarURL)
    }
}
