import SwiftUI

struct BookmarkListView: View {
    @Environment(BookmarkStore.self) private var store
    @State private var path: [BookmarkRoute] = []
    @State private var filter: BookmarkFilter = .repository
    @State private var expandedCounts: [String: Int] = [:]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                filterPicker
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()

                Group {
                    switch filter {
                    case .repository:
                        repositoryContent
                    case .issue:
                        issueContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("ブックマーク")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BookmarkRoute.self) { route in
                switch route {
                case let .repositoryDetail(ownerLogin, repositoryName):
                    RepositoryDetailView(
                        ownerLogin: ownerLogin,
                        repositoryName: repositoryName
                    )
                case let .issueDetail(ownerLogin, repositoryName, number):
                    IssueDetailView(
                        ownerLogin: ownerLogin,
                        repositoryName: repositoryName,
                        issueNumber: number
                    )
                }
            }
        }
    }

    private var filterPicker: some View {
        Picker("種類", selection: $filter) {
            Text("リポジトリ").tag(BookmarkFilter.repository)
            Text("Issue").tag(BookmarkFilter.issue)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Repository Tab

    @ViewBuilder
    private var repositoryContent: some View {
        let repos = store.repositories()
        if repos.isEmpty {
            emptyView(message: "ブックマークしたリポジトリはありません")
        } else {
            List {
                ForEach(repos) { item in
                    if case let .repository(repo) = item {
                        NavigationLink(value: BookmarkRoute.repositoryDetail(
                            ownerLogin: repo.ownerLogin,
                            repositoryName: repo.repositoryName
                        )) {
                            HStack {
                                repositoryRow(repo)
                                Spacer()
                                BookmarkButton(isBookmarked: true) {
                                    store.remove(item)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func repositoryRow(_ repo: RepositoryBookmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(repo.fullName)
                    .font(.headline)
                    .lineLimit(1)
            }

            if let description = repo.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label("\(repo.stargazersCount)", systemImage: "star")
                if let language = repo.language {
                    Label(language, systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Issue Tab (Grouped by Repository)

    @ViewBuilder
    private var issueContent: some View {
        let grouped = groupedIssues()
        if grouped.isEmpty {
            emptyView(message: "ブックマークした Issue はありません")
        } else {
            List {
                ForEach(grouped, id: \.key) { group in
                    issueSection(group: group)
                }
            }
            .listStyle(.plain)
        }
    }

    private func issueSection(group: IssueGroup) -> some View {
        let limit = expandedCounts[group.key, default: 3]
        let visibleCount = min(limit, group.issues.count)
        let visibleIssues = Array(group.issues.prefix(visibleCount))
        let hasMore = group.issues.count > visibleCount
        let isExpanded = visibleCount > 3

        return Section {
            ForEach(visibleIssues, id: \.number) { issue in
                NavigationLink(value: BookmarkRoute.issueDetail(
                    ownerLogin: issue.ownerLogin,
                    repositoryName: issue.repositoryName,
                    number: issue.number
                )) {
                    HStack {
                        issueRow(issue)
                        Spacer()
                        BookmarkButton(isBookmarked: true) {
                            store.remove(.issue(issue))
                        }
                    }
                }
            }

            if hasMore {
                Button {
                    expandedCounts[group.key, default: 3] += 3
                } label: {
                    HStack {
                        Spacer()
                        Text("もっと見る（残り \(group.issues.count - visibleCount) 件）")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Button {
                    expandedCounts[group.key] = 3
                } label: {
                    HStack {
                        Spacer()
                        Text("縮める")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            NavigationLink(value: BookmarkRoute.repositoryDetail(
                ownerLogin: group.ownerLogin,
                repositoryName: group.repositoryName
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.caption)
                    Text(group.key)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func issueRow(_ issue: IssueBookmark) -> some View {
        HStack(alignment: .top, spacing: 10) {
            issueStateIcon(state: issue.state, isPR: issue.isPullRequest)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("#\(issue.number)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func issueStateIcon(state: IssueState, isPR: Bool) -> some View {
        Group {
            if isPR {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(state == .open ? .green : .purple)
            } else {
                Image(systemName: state == .open ? "circle.circle" : "checkmark.circle.fill")
                    .foregroundStyle(state == .open ? .green : .purple)
            }
        }
        .font(.body)
    }

    // MARK: - Grouping

    private func groupedIssues() -> [IssueGroup] {
        var dict: [String: [IssueBookmark]] = [:]
        var order: [String] = []

        for item in store.issues() {
            if case let .issue(issue) = item {
                let key = "\(issue.ownerLogin)/\(issue.repositoryName)"
                if dict[key] == nil {
                    order.append(key)
                }
                dict[key, default: []].append(issue)
            }
        }

        return order.compactMap { key in
            guard var issues = dict[key], let first = issues.first else { return nil }
            issues.sort { $0.createdAt < $1.createdAt }
            return IssueGroup(
                key: key,
                ownerLogin: first.ownerLogin,
                repositoryName: first.repositoryName,
                issues: issues
            )
        }
    }

    // MARK: - Empty

    private func emptyView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum BookmarkFilter {
    case repository
    case issue
}

private struct IssueGroup {
    let key: String
    let ownerLogin: String
    let repositoryName: String
    let issues: [IssueBookmark]
}

#Preview("Empty") {
    BookmarkListView()
        .environment(BookmarkStore(items: []))
}

#Preview("Repositories") {
    BookmarkListView()
        .environment(BookmarkStore(items: [
            .repository(RepositoryBookmark(
                ownerLogin: "apple",
                repositoryName: "swift",
                fullName: "apple/swift",
                description: "The Swift Programming Language",
                stargazersCount: 67000,
                language: "C++",
                createdAt: Date()
            )),
            .repository(RepositoryBookmark(
                ownerLogin: "Alamofire",
                repositoryName: "Alamofire",
                fullName: "Alamofire/Alamofire",
                description: "Elegant HTTP Networking in Swift",
                stargazersCount: 41000,
                language: "Swift",
                createdAt: Date()
            )),
        ]))
}

#Preview("Issues Grouped") {
    BookmarkListView()
        .environment(BookmarkStore(items: [
            .issue(IssueBookmark(
                ownerLogin: "apple",
                repositoryName: "swift",
                number: 42,
                title: "Swift 6 strict concurrency でのコンパイルエラー",
                state: .open,
                isPullRequest: false,
                createdAt: Date()
            )),
            .issue(IssueBookmark(
                ownerLogin: "apple",
                repositoryName: "swift",
                number: 45,
                title: "async/await への移行",
                state: .open,
                isPullRequest: true,
                createdAt: Date()
            )),
            .issue(IssueBookmark(
                ownerLogin: "apple",
                repositoryName: "swift",
                number: 38,
                title: "README にインストール手順を追加",
                state: .closed,
                isPullRequest: false,
                createdAt: Date()
            )),
            .issue(IssueBookmark(
                ownerLogin: "apple",
                repositoryName: "swift",
                number: 50,
                title: "CI パイプラインの最適化",
                state: .open,
                isPullRequest: true,
                createdAt: Date()
            )),
            .issue(IssueBookmark(
                ownerLogin: "Alamofire",
                repositoryName: "Alamofire",
                number: 10,
                title: "リクエストタイムアウトの設定",
                state: .open,
                isPullRequest: false,
                createdAt: Date()
            )),
        ]))
}
