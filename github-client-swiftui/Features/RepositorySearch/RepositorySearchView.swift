import SwiftUI

struct RepositorySearchView: View {
    @State private var model = RepositorySearchModel()
    @State private var path: [RepositorySearchRoute] = []
    @FocusState private var isQueryFieldFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                Divider()

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("リポジトリ検索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RepositorySearchRoute.self) { route in
                switch route {
                case let .repositoryDetail(ownerLogin, repositoryName):
                    Text("リポジトリ詳細(未実装)\n\(ownerLogin)/\(repositoryName)")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .onAppear { model.onAppear() }
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

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            idlePlaceholder
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(isEmpty):
            if isEmpty {
                emptyView
            } else {
                repositoryList
            }
        case let .error(message):
            errorView(message: message)
        }
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

    private var repositoryList: some View {
        List(model.repositories) { repo in
            NavigationLink(value: RepositorySearchRoute.repositoryDetail(
                ownerLogin: repo.owner.login,
                repositoryName: repo.name
            )) {
                RepositoryRow(repository: repo)
            }
        }
        .listStyle(.plain)
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
}
