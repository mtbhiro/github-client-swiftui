import Foundation

nonisolated enum GitHubHttpClient {
    static let shared: any HttpClient = URLSessionHttpClient(
        baseURL: URL(string: "https://api.github.com")!
    )
}
