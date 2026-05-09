import SwiftUI

struct IssueDetailView: View {
    @State private var model: IssueDetailModel

    init(
        fullName: GitHubRepoFullName,
        issueNumber: Int,
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository()
    ) {
        _model = State(initialValue: IssueDetailModel(
            fullName: fullName,
            issueNumber: issueNumber,
            repository: repository
        ))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(issue):
                issueContent(issue)
            case let .error(message):
                errorView(message: message)
            }
        }
        .navigationTitle(model.phase.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    private func issueContent(_ issue: GitHubIssueDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection(issue)
                Divider()
                if let body = issue.body, !body.isEmpty {
                    bodySection(body)
                    Divider()
                }
                commentsSection
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func headerSection(_ issue: GitHubIssueDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AsyncImage(url: issue.user.avatarUrl) { image in
                    image.resizable()
                } placeholder: {
                    Color(.systemGray5)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.user.login)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(issue.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                stateBadge(issue.state)
            }

            Text(issue.title)
                .font(.title3)
                .fontWeight(.bold)

            if !issue.labels.isEmpty {
                labelsView(issue.labels)
            }

            HStack(spacing: 16) {
                Label("\(issue.commentsCount)", systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: issue.htmlUrl) {
                    Label("GitHub で開く", systemImage: "arrow.up.right")
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private func stateBadge(_ state: IssueState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: state == .open ? "circle.circle" : "checkmark.circle.fill")
                .font(.caption)
            Text(state == .open ? "Open" : "Closed")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(state == .open ? Color.green.opacity(0.15) : Color.purple.opacity(0.15))
        .foregroundStyle(state == .open ? .green : .purple)
        .clipShape(Capsule())
    }

    private func labelsView(_ labels: [GitHubLabel]) -> some View {
        HStack(spacing: 4) {
            ForEach(labels) { label in
                Text(label.name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: label.color).opacity(0.2))
                    .foregroundStyle(Color(hex: label.color))
                    .clipShape(Capsule())
            }
        }
    }

    private func bodySection(_ body: String) -> some View {
        Text(body)
            .font(.body)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("コメント")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            switch model.commentsPhase {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            case .loaded:
                if model.comments.isEmpty {
                    Text("コメントはありません")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(model.comments) { comment in
                        commentRow(comment)
                        if comment.id != model.comments.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            case let .error(message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("再試行") {
                        model.retryComments()
                    }
                    .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .background(Color(.systemBackground))
    }

    private func commentRow(_ comment: GitHubIssueComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: comment.user.avatarUrl) { image in
                image.resizable()
            } placeholder: {
                Color(.systemGray5)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.user.login)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(comment.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(comment.body)
                    .font(.callout)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

private extension IssueDetailModel.Phase {
    var navigationTitle: String {
        switch self {
        case .loading:
            "読み込み中..."
        case let .loaded(issue):
            "#\(issue.number)"
        case .error:
            "エラー"
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview("Loaded") {
    NavigationStack {
        IssueDetailView(
            fullName: GitHubRepoFullName(ownerLogin: "apple", name: "swift"),
            issueNumber: 42,
            repository: MockGithubRepoRepository()
        )
    }
}

#Preview("Error") {
    NavigationStack {
        IssueDetailView(
            fullName: GitHubRepoFullName(ownerLogin: "apple", name: "swift"),
            issueNumber: 42,
            repository: MockGithubRepoRepository(
                issueDetailResult: .failure(URLError(.notConnectedToInternet))
            )
        )
    }
}
