import Foundation

nonisolated struct GitHubRepoFullName: Sendable, Hashable, Codable, CustomStringConvertible {
    let ownerLogin: String
    let name: String

    var description: String {
        "\(ownerLogin)/\(name)"
    }
}
