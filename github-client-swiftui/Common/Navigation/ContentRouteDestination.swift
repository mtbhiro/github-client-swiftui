import SwiftUI

struct ContentRouteDestination: ViewModifier {
    let repository: any GithubRepoRepositoryProtocol

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ContentRoute.self) { route in
                switch route {
                case let .repositoryDetail(fullName):
                    RepositoryDetailView(
                        fullName: fullName,
                        repository: repository
                    )
                case let .issueList(fullName):
                    IssueListView(
                        fullName: fullName,
                        repository: repository
                    )
                case let .issueDetail(fullName, number):
                    IssueDetailView(
                        fullName: fullName,
                        issueNumber: number,
                        repository: repository
                    )
                }
            }
    }
}

extension View {
    func contentRouteDestination(repository: any GithubRepoRepositoryProtocol) -> some View {
        modifier(ContentRouteDestination(repository: repository))
    }
}
