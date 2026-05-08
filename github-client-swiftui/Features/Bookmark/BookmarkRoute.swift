import Foundation

enum BookmarkRoute: Hashable {
    case repositoryDetail(ownerLogin: String, repositoryName: String)
    case issueDetail(ownerLogin: String, repositoryName: String, number: Int)
}
