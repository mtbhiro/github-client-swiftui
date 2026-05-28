import SwiftUI

struct RepositorySearchView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(BookmarkStore.self) private var bookmarkStore
    @Environment(\.githubRepository) private var repository
    @State private var model: RepositorySearchModel
    @State private var isShowingFilters = false
    @FocusState private var isQueryFieldFocused: Bool

    init(cache: RepositorySearchCache, repository: any GithubRepoRepositoryProtocol) {
        _model = State(initialValue: RepositorySearchModel(repository: repository, cache: cache))
    }

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

                // loaded / pagingLoading / pagingError は同一 List で扱い、Group switch の case 切替で
                // View identity が分かれてスクロール位置がリセットされるのを防ぐ。
                Group {
                    if let listState = model.phase.listState {
                        repositoryList(
                            listState.state,
                            isPagingLoading: listState.isPagingLoading,
                            isPagingError: listState.isPagingError
                        )
                    } else {
                        switch model.phase {
                        case .idle:
                            idlePlaceholder
                        case .loading:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case let .noResults(query):
                            noResultsView(query: query)
                        case .errorNetwork:
                            errorNetworkView
                        case let .errorRateLimited(resetDate):
                            errorRateLimitedView(resetDate: resetDate)
                        case .loaded, .pagingLoading, .pagingError:
                            EmptyView() // 上の if 分岐でハンドル済み
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("リポジトリ検索")
            .navigationBarTitleDisplayMode(.inline)
            .contentRouteDestination(repository: repository)
            .onChange(of: model.query) { oldValue, newValue in
                guard newValue != oldValue else { return }
                model.onQueryChanged()
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
        _ state: RepositorySearchModel.LoadedState,
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
        .refreshable { await model.refresh() }
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
        return NavigationLink(value: ContentRoute.repositoryDetail(repo.fullName)) {
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
        ErrorStateView(
            icon: "wifi.exclamationmark",
            message: "通信に失敗しました",
            retryAction: { model.retry() }
        )
    }

    private func errorRateLimitedView(resetDate: Date?) -> some View {
        ErrorStateView(
            icon: "clock.badge.exclamationmark",
            message: "API 利用制限に達しました",
            detail: "解除予定: \(formattedResetDate(resetDate))",
            retryAction: { model.retry() }
        )
    }

    private func formattedResetDate(_ date: Date?) -> String {
        guard let date else { return "時刻不明" }
        return DateFormatters.rateLimitReset.string(from: date)
    }
}

#Preview("idle") {
    RepositorySearchView(cache: RepositorySearchCache(), repository: MockGithubRepoRepository())
        .environment(AppCoordinator())
        .environment(BookmarkStore(items: []))
}
