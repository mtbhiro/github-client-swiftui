import Foundation

nonisolated protocol GitHubAuthServiceProtocol: Sendable {
    func requestDeviceCode() async throws -> GitHubDeviceCode
    func pollAccessToken(deviceCode: String) async throws -> GitHubAuthTokenOutcome
    func fetchAuthenticatedUser(token: String) async throws -> GitHubAuthenticatedUser
    func saveToken(_ token: String) throws
    func loadToken() -> String?
    func clearToken() throws
    func clientID() throws -> String
}

nonisolated enum GitHubAuthConfigError: Error, Equatable {
    case missingClientID
}

nonisolated struct GitHubAuthHosts: Sendable {
    let oauth: ApiHost
    let api: ApiHost

    static let production = GitHubAuthHosts(
        // swiftlint:disable:next force_unwrapping
        oauth: .custom(URL(string: "https://github.com")!),
        api: .github
    )
}

nonisolated struct GitHubAuthService: GitHubAuthServiceProtocol {
    private let httpClient: HttpClient
    private let keychain: KeychainStorage
    private let hosts: GitHubAuthHosts
    private let clientIDProvider: @Sendable () -> String?

    init(
        httpClient: HttpClient = URLSessionHttpClient(),
        keychain: KeychainStorage = KeychainStorage(
            service: "hiroc19.github-client-swiftui.auth",
            account: "access_token"
        ),
        hosts: GitHubAuthHosts = .production,
        clientIDProvider: @Sendable @escaping () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String
        }
    ) {
        self.httpClient = httpClient
        self.keychain = keychain
        self.hosts = hosts
        self.clientIDProvider = clientIDProvider
    }

    func requestDeviceCode() async throws -> GitHubDeviceCode {
        let id = try clientID()
        let request = HttpRequest(
            host: hosts.oauth,
            method: .post,
            path: "/login/device/code",
            queryItems: [
                URLQueryItem(name: "client_id", value: id),
                URLQueryItem(name: "scope", value: "read:user"),
            ],
            headers: ["Accept": "application/json"]
        )
        let dto: GitHubDeviceCodeDTO = try await httpClient.send(request)
        return dto.toDomain()
    }

    func pollAccessToken(deviceCode: String) async throws -> GitHubAuthTokenOutcome {
        let id = try clientID()
        let request = HttpRequest(
            host: hosts.oauth,
            method: .post,
            path: "/login/oauth/access_token",
            queryItems: [
                URLQueryItem(name: "client_id", value: id),
                URLQueryItem(name: "device_code", value: deviceCode),
                URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code"),
            ],
            headers: ["Accept": "application/json"]
        )
        let dto: GitHubAuthTokenResponseDTO = try await httpClient.send(request)
        return dto.outcome
    }

    func fetchAuthenticatedUser(token: String) async throws -> GitHubAuthenticatedUser {
        let request = HttpRequest(
            host: hosts.api,
            path: "/user",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            ]
        )
        let dto: GitHubAuthenticatedUserDTO = try await httpClient.send(request)
        return dto.toDomain()
    }

    func saveToken(_ token: String) throws {
        try keychain.save(token)
    }

    func loadToken() -> String? {
        keychain.load()
    }

    func clearToken() throws {
        try keychain.delete()
    }

    func clientID() throws -> String {
        guard let id = clientIDProvider(), !id.isEmpty else {
            throw GitHubAuthConfigError.missingClientID
        }
        return id
    }
}
