import Foundation

nonisolated enum GitHubAuthTokenOutcome: Sendable, Equatable {
    case success(accessToken: String)
    case pending
    case slowDown
    case accessDenied
    case expiredToken
    case otherError(code: String)
}

nonisolated struct GitHubAuthTokenResponseDTO: Decodable, Sendable {
    let outcome: GitHubAuthTokenOutcome

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let token = try container.decodeIfPresent(String.self, forKey: .accessToken), !token.isEmpty {
            outcome = .success(accessToken: token)
            return
        }
        let errorCode = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        switch errorCode {
        case "authorization_pending":
            outcome = .pending
        case "slow_down":
            outcome = .slowDown
        case "access_denied":
            outcome = .accessDenied
        case "expired_token":
            outcome = .expiredToken
        default:
            outcome = .otherError(code: errorCode)
        }
    }
}
