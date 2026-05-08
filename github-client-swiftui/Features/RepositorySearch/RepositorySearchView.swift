import SwiftUI

struct RepositorySearchView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BookmarkStore.self) private var bookmarkStore
    @State private var model = RepositorySearchModel()
    @FocusState private var isQueryFieldFocused: Bool

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.searchPath) {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                Divider()

                Group {
                    switch model.phase {
                    case .idle:
                        idlePlaceholder
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .loaded(state):
                        if state.repositories.isEmpty {
                            emptyView
                        } else {
                            repositoryList(state)
                        }
                    case let .error(message):
                        errorView(message: message)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("リポジトリ検索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case let .repositoryDetail(ownerLogin, repositoryName):
                    RepositoryDetailView(
                        ownerLogin: ownerLogin,
                        repositoryName: repositoryName,
                        issueListRoute: SearchRoute.issueList(
                            ownerLogin: ownerLogin,
                            repositoryName: repositoryName
                        )
                    )
                case let .issueList(ownerLogin, repositoryName):
                    IssueListView(
                        ownerLogin: ownerLogin,
                        repositoryName: repositoryName,
                        issueDetailRoute: { number in
                            SearchRoute.issueDetail(
                                ownerLogin: ownerLogin,
                                repositoryName: repositoryName,
                                number: number
                            )
                        }
                    )
                case let .issueDetail(ownerLogin, repositoryName, number):
                    IssueDetailView(
                        ownerLogin: ownerLogin,
                        repositoryName: repositoryName,
                        issueNumber: number
                    )
                }
            }
            .onDisappear { model.onDisappear() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("リポジトリを検索", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .focused($isQueryFieldFocused)
                    .onSubmit {
                        isQueryFieldFocused = false
                        model.onSubmit()
                    }

                if !model.query.isEmpty {
                    Button {
                        model.clearQuery()
                        isQueryFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("検索文字列をクリア")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            if isQueryFieldFocused {
                Button("キャンセル") {
                    model.clearQuery()
                    isQueryFieldFocused = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isQueryFieldFocused)
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("キーワードを入力してリポジトリを検索")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("該当するリポジトリが見つかりませんでした")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func repositoryList(_ state: LoadedRepositories) -> some View {
        List {
            ForEach(state.repositories) { repo in
                repositoryRow(repo)
            }

            if state.hasMorePages {
                ProgressView()
                    .id(state.repositories.count)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .onAppear { model.loadNextPageIfNeeded() }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await model.refresh() }
    }

    private func repositoryRow(_ repo: GitHubRepo) -> some View {
        let item = BookmarkItem.repository(RepositoryBookmark(
            ownerLogin: repo.owner.login,
            repositoryName: repo.name,
            fullName: repo.fullName,
            description: repo.description,
            stargazersCount: repo.stargazersCount,
            language: repo.language,
            createdAt: Date()
        ))
        return NavigationLink(value: SearchRoute.repositoryDetail(
            ownerLogin: repo.owner.login,
            repositoryName: repo.name
        )) {
            HStack {
                RepositoryRow(repository: repo)
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

#Preview {
    RepositorySearchView()
        .environment(AppCoordinator())
        .environment(BookmarkStore(items: []))
}
