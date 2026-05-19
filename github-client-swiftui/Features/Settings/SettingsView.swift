import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(GitHubAuthState.self) private var authState
    @Environment(RateLimitObserver.self) private var rateLimit
    @Environment(AuthFactory.self) private var authFactory

    @State private var model: SettingsModel?

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.settingsPath) {
            settingsForm
                .navigationTitle("設定")
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .deviceFlow:
                        DeviceFlowView(model: authFactory.makeDeviceFlowModel { token, user in
                            authState.completeSignIn(token: token, user: user)
                            coordinator.popToRoot(of: .settings)
                        })
                    }
                }
        }
        .task {
            if model == nil {
                model = SettingsModel(
                    authState: authState,
                    rateLimit: rateLimit,
                    service: authFactory.service
                )
            }
            model?.refreshProfile()
        }
        .onChange(of: authState.phase) { _, _ in
            model?.onAuthPhaseChanged()
            // 起動時の signedIn 復元、または Device Flow 経由で sign-in した直後にも
            // refreshProfile を流すと、cached → loaded への遷移ができる。
            model?.refreshProfile()
        }
    }

    @ViewBuilder
    private var settingsForm: some View {
        if let model {
            Form {
                Section("アカウント") {
                    authSection(model: model)
                }
                Section("レート制限") {
                    rateLimitRow
                }
            }
            .confirmationDialog(
                "ログアウトしますか？",
                isPresented: Binding(
                    get: { model.logoutConfirmationVisible },
                    set: { newValue in
                        if !newValue { model.cancelLogout() }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("ログアウト", role: .destructive) {
                    model.confirmLogout()
                }
                Button("キャンセル", role: .cancel) {
                    model.cancelLogout()
                }
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func authSection(model: SettingsModel) -> some View {
        switch model.profileState {
        case .hidden:
            Button {
                authState.beginSigningIn()
                coordinator.settingsPath.append(SettingsRoute.deviceFlow)
            } label: {
                Label("GitHub にログイン", systemImage: "person.crop.circle.badge.checkmark")
            }
            .accessibilityIdentifier("settings.login")

        case .loading:
            HStack(spacing: 12) {
                Circle()
                    .fill(.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("読み込み中…")
                        .foregroundStyle(.secondary)
                }
            }
            logoutButton(model: model)

        case let .loaded(user):
            profileRow(user: user, cached: false)
            logoutButton(model: model)

        case let .cached(user):
            profileRow(user: user, cached: true)
            logoutButton(model: model)
        }
    }

    private func profileRow(user: GitHubAuthenticatedUser, cached: Bool) -> some View {
        HStack(spacing: 12) {
            avatar(url: user.avatarURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.login)
                    .font(.headline)
                if let name = user.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if cached {
                    Text("最新の取得に失敗しました")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityIdentifier("settings.profile")
    }

    private func avatar(url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(.gray.opacity(0.2))
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        fallbackAvatar
                    @unknown default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.gray)
    }

    private func logoutButton(model: SettingsModel) -> some View {
        Button(role: .destructive) {
            model.requestLogout()
        } label: {
            Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .accessibilityIdentifier("settings.logout")
    }

    @ViewBuilder
    private var rateLimitRow: some View {
        if let snapshot = rateLimit.snapshot {
            HStack {
                Text("上限")
                Spacer()
                Text("\(snapshot.remaining) / \(snapshot.limit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityIdentifier("settings.rateLimit")
        } else {
            HStack {
                Text("上限")
                Spacer()
                Text("未取得")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("settings.rateLimit")
        }
    }
}
