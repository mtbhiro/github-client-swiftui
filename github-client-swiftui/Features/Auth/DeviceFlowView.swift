import SwiftUI

struct DeviceFlowView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppCoordinator.self) private var coordinator
    let model: DeviceFlowModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("GitHub にログイン")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.start()
        }
        .onDisappear {
            model.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loadingDeviceCode:
            loadingView
        case let .polling(code):
            pollingView(code: code)
        case let .errorDeviceCode(reason):
            errorDeviceCodeView(reason)
        case .errorAccessDenied:
            errorAccessDeniedView
        case .errorExpired:
            errorExpiredView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("認証コードを準備しています…")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 60)
        .accessibilityIdentifier("deviceFlow.loading")
    }

    private func pollingView(code: GitHubDeviceCode) -> some View {
        VStack(spacing: 20) {
            Text("以下のコードを GitHub のページで入力してください。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text(code.userCode)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(.gray.opacity(0.15), in: .rect(cornerRadius: 12))
                .accessibilityLabel(spokenUserCode(code.userCode))
                .accessibilityIdentifier("deviceFlow.userCode")

            Text(code.verificationURL.absoluteString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(spacing: 12) {
                Button {
                    openURL(code.verificationURL)
                } label: {
                    Label("ブラウザで開く", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("deviceFlow.openBrowser")

                Button {
                    UIPasteboard.general.string = code.userCode
                } label: {
                    Label("コードをコピー", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("deviceFlow.copyCode")

                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("キャンセル")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("deviceFlow.cancel")
            }

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("認可を待っています…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private func errorDeviceCodeView(_ reason: DeviceFlowModel.DeviceCodeError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message(for: reason))
                .multilineTextAlignment(.center)

            if reason == .network {
                Button("再試行") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("deviceFlow.retry")
            }
            Button("閉じる") { dismiss() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("deviceFlow.close")
        }
        .padding(.vertical, 40)
    }

    private var errorAccessDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("認可がキャンセルされました")
                .multilineTextAlignment(.center)
            Button("閉じる") { dismiss() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("deviceFlow.close")
        }
        .padding(.vertical, 40)
    }

    private var errorExpiredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("コードの有効期限が切れました")
                .multilineTextAlignment(.center)
            Button("再開") { model.restart() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("deviceFlow.restart")
            Button("閉じる") { dismiss() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("deviceFlow.close")
        }
        .padding(.vertical, 40)
    }

    private func dismiss() {
        @Bindable var coordinator = coordinator
        coordinator.popToRoot(of: .settings)
    }

    private func message(for reason: DeviceFlowModel.DeviceCodeError) -> String {
        switch reason {
        case .network:
            return "通信に失敗しました。電波状況をご確認のうえ再試行してください。"
        case .config:
            return "アプリの設定に問題があります。Config.xcconfig の GITHUB_OAUTH_CLIENT_ID をご確認ください。"
        }
    }

    /// 「WDJB-MJHT」を「W D J B - M J H T」のように 1 文字ずつ読み上げさせる。
    /// （PRD §8.2 アクセシビリティ要件）
    private func spokenUserCode(_ code: String) -> String {
        code.map { String($0) }.joined(separator: " ")
    }
}

#Preview("polling") {
    let coordinator = AppCoordinator()
    let mockRepository = MockGitHubAuthRepository()
    NavigationStack {
        DeviceFlowView(
            model: DeviceFlowModel(
                repository: mockRepository,
                authState: GitHubAuthState(repository: mockRepository),
                coordinator: coordinator,
                intervalScale: 1.0
            )
        )
    }
    .environment(coordinator)
}
