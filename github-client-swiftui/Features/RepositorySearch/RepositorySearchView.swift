import SwiftUI

struct RepositorySearchView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BookmarkStore.self) private var bookmarkStore
    @State private var model = RepositorySearchModel()
    @State private var isShowingFilters = false
    @FocusState private var isQueryFieldFocused: Bool

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.searchPath) {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                if !model.chips.isEmpty {
                    RepositorySearchChipRow(
                        chips: model.chips,
                        onRemove: { chip in model.removeChip(chip) }
                    )
                }

                HStack {
                    Button {
                        isShowingFilters = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("条件")
                        }
                        .font(.subheadline)
                    }
                    .accessibilityLabel("検索条件を編集")

                    Spacer()

                    RepositorySearchSortMenu(current: model.sort) { newSort in
                        model.setSort(newSort)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                Divider()

                Group {
                    switch model.phase {
                    case .idle:
                        idlePlaceholder
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .loaded(state):
                        repositoryList(state, isPagingLoading: false, isPagingError: false)
                    case let .pagingLoading(state):
                        repositoryList(state, isPagingLoading: true, isPagingError: false)
                    case let .pagingError(state):
                        repositoryList(state, isPagingLoading: false, isPagingError: true)
                    case let .noResults(q):
                        noResultsView(query: q)
                    case .errorNetwork:
                        errorNetworkView
                    case let .errorRateLimited(resetDate):
                        errorRateLimitedView(resetDate: resetDate)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("リポジトリ検索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SearchRoute.self) { route in
                switch route {
                case let .repositoryDetail(fullName):
                    RepositoryDetailView(
                        fullName: fullName,
                        issueListRoute: SearchRoute.issueList(fullName)
                    )
                case let .issueList(fullName):
                    IssueListView(
                        fullName: fullName,
                        issueDetailRoute: { number in
                            SearchRoute.issueDetail(fullName, number: number)
                        }
                    )
                case let .issueDetail(fullName, number):
                    IssueDetailView(
                        fullName: fullName,
                        issueNumber: number
                    )
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                RepositorySearchFiltersView(initial: model.appliedQualifiers) { qualifiers in
                    model.applyQualifiers(qualifiers)
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
                        model.query = ""
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
                    model.query = ""
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
            Text("キーワードを入力してください")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noResultsView(query: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("\"\(query)\" に一致するリポジトリは見つかりませんでした")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func repositoryList(
        _ state: RepositorySearchLoadedState,
        isPagingLoading: Bool,
        isPagingError: Bool
    ) -> some View {
        List {
            ForEach(state.repositories) { repo in
                repositoryRow(repo)
            }

            if state.hasMorePages || isPagingLoading || isPagingError {
                listFooter(isPagingLoading: isPagingLoading, isPagingError: isPagingError, hasMorePages: state.hasMorePages)
                    .listRowSeparator(.hidden)
            } else if state.repositories.count >= RepositorySearchModel.maxAccumulated {
                Text("これ以上の結果は表示できません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func listFooter(isPagingLoading: Bool, isPagingError: Bool, hasMorePages: Bool) -> some View {
        if isPagingError {
            Button("再試行") { model.retryPaging() }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else if isPagingLoading {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else if hasMorePages {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .onAppear { model.loadNextPageIfNeeded() }
        }
    }

    private func repositoryRow(_ repo: GitHubRepo) -> some View {
        // ブックマーク有無の判定は BookmarkItem.id (= "repo:<fullName>") で行うため、
        // createdAt は判定に影響しない。一方、toggle 時に保存される `createdAt` は
        // 「タップ瞬間の日時」を意味させたいので、描画毎ではなくクロージャ内で生成する。
        let lookupItem = BookmarkItem.repository(RepositoryBookmark(
            fullName: repo.fullName,
            description: repo.description,
            stargazersCount: repo.stargazersCount,
            language: repo.language,
            createdAt: .distantPast
        ))
        return NavigationLink(value: SearchRoute.repositoryDetail(repo.fullName)) {
            HStack {
                RepositoryRow(repository: repo)
                Spacer()
                BookmarkButton(isBookmarked: bookmarkStore.contains(lookupItem)) {
                    let item = BookmarkItem.repository(RepositoryBookmark(
                        fullName: repo.fullName,
                        description: repo.description,
                        stargazersCount: repo.stargazersCount,
                        language: repo.language,
                        createdAt: Date()
                    ))
                    bookmarkStore.toggle(item)
                }
                .accessibilityIdentifier("BookmarkButton-\(repo.fullName)")
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var errorNetworkView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("通信に失敗しました")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("再試行") { model.retry() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorRateLimitedView(resetDate: Date?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("API 利用制限に達しました")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("解除予定: \(formattedResetDate(resetDate))")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("再試行") { model.retry() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedResetDate(_ date: Date?) -> String {
        guard let date else { return "時刻不明" }
        return Self.rateLimitResetFormatter.string(from: date)
    }

    private static let rateLimitResetFormatter: DateFormatter = {
        let f = DateFormatter()
        // PRD §4.3.2: 端末ローカルタイムゾーンで yyyy-MM-dd HH:mm。
        // 数字フォーマット固定なので en_US_POSIX を使う。
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

#Preview("idle") {
    RepositorySearchView()
        .environment(AppCoordinator())
        .environment(BookmarkStore(items: []))
}
