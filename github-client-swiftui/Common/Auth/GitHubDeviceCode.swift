import Foundation

nonisolated struct GitHubDeviceCode: Sendable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int
}

nonisolated struct GitHubDeviceCodeDTO: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    func toDomain() -> GitHubDeviceCode {
        GitHubDeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: URL(string: verificationURI) ?? URL(string: "https://github.com/login/device")!,
            expiresIn: expiresIn,
            interval: interval
        )
    }
}
