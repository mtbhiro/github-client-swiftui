import SwiftUI

struct IssueListView: View {
    @Environment(BookmarkStore.self) private var bookmarkStore
    @State private var model: IssueListModel
    @State private var path: [IssueListRoute] = []

    init(
        ownerLogin: String,
        repositoryName: String,
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository()
    ) {
        _model = State(initialValue: IssueListModel(
            ownerLogin: ownerLogin,
            repositoryName: repositoryName,
            repository: repository
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(isEmpty):
                    if isEmpty {
                        emptyView
                    } else {
                        issueList
                    }
                case let .error(message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Issues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: IssueListRoute.self) { route in
                switch route {
                case let .issueDetail(number):
                    IssueDetailView(
                        ownerLogin: model.ownerLogin,
                        repositoryName: model.repositoryName,
                        issueNumber: number
                    )
                }
            }
            .onAppear { model.onAppear() }
            .onDisappear { model.onDisappear() }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Issue はありません")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var issueList: some View {
        List {
            ForEach(model.issues) { issue in
                issueRow(issue)
            }

            if model.hasMorePages {
                ProgressView()
                    .id(model.issues.count)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .onAppear { model.loadNextPageIfNeeded() }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
    }

    private func issueRow(_ issue: GitHubIssue) -> some View {
        let item = BookmarkItem.issue(IssueBookmark(
            ownerLogin: model.ownerLogin,
            repositoryName: model.repositoryName,
            number: issue.number,
            title: issue.title,
            state: issue.state,
            isPullRequest: issue.isPullRequest,
            createdAt: Date()
        ))
        return NavigationLink(value: IssueListRoute.issueDetail(number: issue.number)) {
            HStack {
                IssueRow(issue: issue)
                Spacer()
                BookmarkButton(isBookmarked: bookmarkStore.contains(item)) {
                    bookmarkStore.toggle(item)
                }
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("再試行") {
                model.retry()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum IssueListRoute: Hashable {
    case issueDetail(number: Int)
}

#Preview("Loaded") {
    IssueListView(
        ownerLogin: "apple",
        repositoryName: "swift",
        repository: MockGithubRepoRepository()
    )
    .environment(BookmarkStore(items: []))
}

#Preview("Empty") {
    IssueListView(
        ownerLogin: "apple",
        repositoryName: "swift",
        repository: MockGithubRepoRepository(issuesResult: .success([]))
    )
    .environment(BookmarkStore(items: []))
}

#Preview("Error") {
    IssueListView(
        ownerLogin: "apple",
        repositoryName: "swift",
        repository: MockGithubRepoRepository(
            issuesResult: .failure(URLError(.notConnectedToInternet))
        )
    )
    .environment(BookmarkStore(items: []))
}
