import Foundation

protocol RepositorySearchRepositoryProtocol: Sendable {
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository]
}

struct RepositorySearchRepository: RepositorySearchRepositoryProtocol {
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] {
        // TODO: URLSession を使った実際の API 呼び出しを実装する
        fatalError("Not implemented")
    }
}
