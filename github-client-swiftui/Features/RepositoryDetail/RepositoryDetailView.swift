import SwiftUI

struct RepositoryDetailView: View {
    @State private var model: RepositoryDetailModel

    init(ownerLogin: String, repositoryName: String, repository: GithubRepoRepositoryProtocol = GithubRepoRepository()) {
        _model = State(initialValue: RepositoryDetailModel(
            ownerLogin: ownerLogin,
            repositoryName: repositoryName,
            repository: repository
        ))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(repo):
                repositoryContent(repo)
            case let .error(message):
                errorView(message: message)
            }
        }
        .navigationTitle(model.phase.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    private func repositoryContent(_ repo: GitHubRepoDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection(repo)
                Divider()
                statsSection(repo)
                Divider()
                detailSection(repo)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func headerSection(_ repo: GitHubRepoDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: repo.owner.avatarUrl) { image in
                    image.resizable()
                } placeholder: {
                    Color(.systemGray5)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.owner.login)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(repo.name)
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }

            if let description = repo.description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if !repo.topics.isEmpty {
                topicsView(repo.topics)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private func topicsView(_ topics: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(topics, id: \.self) { topic in
                Text(topic)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    private func statsSection(_ repo: GitHubRepoDetail) -> some View {
        HStack(spacing: 0) {
            statItem(icon: "star", label: "Stars", value: repo.stargazersCount.formatted())
            Divider().frame(height: 40)
            statItem(icon: "tuningfork", label: "Forks", value: repo.forksCount.formatted())
            Divider().frame(height: 40)
            statItem(icon: "eye", label: "Watchers", value: repo.watchersCount.formatted())
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailSection(_ repo: GitHubRepoDetail) -> some View {
        VStack(spacing: 0) {
            if let language = repo.language {
                detailRow(icon: "chevron.left.forwardslash.chevron.right", label: "言語", value: language)
                Divider().padding(.leading, 44)
            }
            detailRow(icon: "arrow.branch", label: "デフォルトブランチ", value: repo.defaultBranch)
            Divider().padding(.leading, 44)
            detailRow(icon: "exclamationmark.circle", label: "Issues", value: "\(repo.openIssuesCount)")
            Divider().padding(.leading, 44)
            linkRow(icon: "safari", label: "GitHub で開く", url: repo.htmlUrl)
        }
        .background(Color(.systemBackground))
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func linkRow(icon: String, label: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

private extension RepositoryDetailModel.Phase {
    var title: String {
        switch self {
        case .loading:
            "読み込み中..."
        case let .loaded(repo):
            repo.fullName
        case .error:
            "エラー"
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            )
            subview.place(at: point, proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

#Preview("Loaded") {
    NavigationStack {
        RepositoryDetailView(
            ownerLogin: "apple",
            repositoryName: "swift",
            repository: MockGithubRepoRepository()
        )
    }
}

#Preview("Error") {
    NavigationStack {
        RepositoryDetailView(
            ownerLogin: "apple",
            repositoryName: "swift",
            repository: MockGithubRepoRepository(
                fetchResult: .failure(URLError(.notConnectedToInternet))
            )
        )
    }
}
