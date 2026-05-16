import Foundation

nonisolated struct RepositorySearchPageResult: Sendable, Equatable {
    let repositories: [GitHubRepo]
    let totalCount: Int
    let incompleteResults: Bool
}
