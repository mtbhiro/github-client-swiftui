import Foundation

enum RepositorySearchRoute: Hashable {
    case repositoryDetail(ownerLogin: String, repositoryName: String)
}
