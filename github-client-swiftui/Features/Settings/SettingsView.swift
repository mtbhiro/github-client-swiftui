import SwiftUI

struct SettingsView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(GitHubAuthState.self) private var authState
    @Environment(RateLimitObserver.self) private var rateLimit
    @Environment(AuthFactory.self) private var authFactory

    @State private var logoutConfirmationVisible = false

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack(path: $coordinator.settingsPath) {
            Form {
                Section("アカウント") {
                    authSection
                }
                Section("レート制限") {
                    rateLimitRows
                }
            }
            .navigationTitle("設定")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .deviceFlow:
                    DeviceFlowView(
                        model: authFactory.makeDeviceFlowModel(
                            authState: authState,
                            coordinator: coordinator
                        )
                    )
                }
            }
            .confirmationDialog(
                "ログアウトしますか？",
                isPresented: $logoutConfirmationVisible,
                titleVisibility: .visible
            ) {
                Button("ログアウト", role: .destructive) {
                    authState.logout()
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var authSection: some View {
        switch authState.profilePhase {
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
            logoutButton

        case let .loaded(user):
            profileRow(user: user, cached: false)
            logoutButton

        case let .cached(user):
            profileRow(user: user, cached: true)
            logoutButton
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
        AvatarImageView(url: url, size: 48)
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            logoutConfirmationVisible = true
        } label: {
            Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .accessibilityIdentifier("settings.logout")
    }

    @ViewBuilder
    private var rateLimitRows: some View {
        rateLimitRow(label: "Core API", resource: .core, identifier: "settings.rateLimit.core")
        rateLimitRow(label: "Search API", resource: .search, identifier: "settings.rateLimit.search")
    }

    private func rateLimitRow(label: String, resource: RateLimitResource, identifier: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let snapshot = rateLimit.snapshots[resource] {
                Text("\(snapshot.remaining) / \(snapshot.limit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("未取得")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}
