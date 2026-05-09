import SwiftUI

struct IssueListView<IssueDetailRoute: Hashable>: View {
    @Environment(BookmarkStore.self) private var bookmarkStore
    @State private var model: IssueListModel
    private let issueDetailRoute: (Int) -> IssueDetailRoute

    init(
        fullName: GitHubRepoFullName,
        issueDetailRoute: @escaping (Int) -> IssueDetailRoute,
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository()
    ) {
        _model = State(initialValue: IssueListModel(
            fullName: fullName,
            repository: repository
        ))
        self.issueDetailRoute = issueDetailRoute
    }

    var body: some View {
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
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

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
            fullName: model.fullName,
            number: issue.number,
            title: issue.title,
            state: issue.state,
            isPullRequest: issue.isPullRequest,
            createdAt: Date()
        ))
        return NavigationLink(value: issueDetailRoute(issue.number)) {
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

private let previewFullName = GitHubRepoFullName(ownerLogin: "apple", name: "swift")

#Preview("Loaded") {
    NavigationStack {
        IssueListView(
            fullName: previewFullName,
            issueDetailRoute: { SearchRoute.issueDetail(previewFullName, number: $0) },
            repository: MockGithubRepoRepository()
        )
    }
    .environment(BookmarkStore(items: []))
}

#Preview("Empty") {
    NavigationStack {
        IssueListView(
            fullName: previewFullName,
            issueDetailRoute: { SearchRoute.issueDetail(previewFullName, number: $0) },
            repository: MockGithubRepoRepository(issuesResult: .success([]))
        )
    }
    .environment(BookmarkStore(items: []))
}

#Preview("Error") {
    NavigationStack {
        IssueListView(
            fullName: previewFullName,
            issueDetailRoute: { SearchRoute.issueDetail(previewFullName, number: $0) },
            repository: MockGithubRepoRepository(
                issuesResult: .failure(URLError(.notConnectedToInternet))
            )
        )
    }
    .environment(BookmarkStore(items: []))
}
