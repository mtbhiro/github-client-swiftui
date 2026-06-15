import Foundation
import Observation

@Observable
final class DeviceFlowModel {

    enum DeviceCodeError: Sendable, Equatable {
        case network
        case config
    }

    enum Phase: Sendable, Equatable {
        case loadingDeviceCode
        case polling(GitHubDeviceCode)
        case errorDeviceCode(DeviceCodeError)
        case errorAccessDenied
        case errorExpired
    }

    private(set) var phase: Phase = .loadingDeviceCode

    var inFlightTask: Task<Void, Never>? { currentTask }

    private var currentTask: Task<Void, Never>?
    private let service: GitHubAuthServiceProtocol
    private let authState: GitHubAuthState
    private let coordinator: AppCoordinator
    /// テスト時に polling interval を圧縮するための係数。
    /// `interval` 秒 * `intervalScale` の `Duration` を `Task.sleep` に渡す。
    private let intervalScale: Double

    init(
        service: GitHubAuthServiceProtocol,
        authState: GitHubAuthState,
        coordinator: AppCoordinator,
        intervalScale: Double = 1.0
    ) {
        self.service = service
        self.authState = authState
        self.coordinator = coordinator
        self.intervalScale = intervalScale
    }

    func start() {
        cancelCurrent()
        phase = .loadingDeviceCode
        currentTask = Task { [weak self] in
            await self?.runDeviceFlow()
        }
    }

    func cancel() {
        cancelCurrent()
    }

    func restart() {
        start()
    }

    private func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func runDeviceFlow() async {
        let code: GitHubDeviceCode
        do {
            code = try await service.requestDeviceCode()
        } catch is CancellationError {
            return
        } catch GitHubAuthConfigError.missingClientID {
            phase = .errorDeviceCode(.config)
            return
        } catch {
            phase = .errorDeviceCode(.network)
            return
        }

        guard !Task.isCancelled else { return }
        phase = .polling(code)

        await pollLoop(deviceCode: code)
    }

    private func pollLoop(deviceCode: GitHubDeviceCode) async {
        var intervalSeconds = Double(deviceCode.interval)

        while !Task.isCancelled {
            let waitDuration = Duration.milliseconds(Int(intervalSeconds * 1000 * intervalScale))
            do {
                try await Task.sleep(for: waitDuration)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            if Task.isCancelled { return }

            let outcome: GitHubAuthTokenOutcome
            do {
                outcome = try await service.pollAccessToken(deviceCode: deviceCode.deviceCode)
            } catch is CancellationError {
                return
            } catch {
                // ネットワーク障害 / 5xx 等は polling を継続する（PRD AC-7.4）。
                continue
            }

            if Task.isCancelled { return }

            switch outcome {
            case .pending:
                continue
            case .slowDown:
                intervalSeconds += 5
                continue
            case .accessDenied:
                phase = .errorAccessDenied
                return
            case .expiredToken:
                phase = .errorExpired
                return
            case .otherError:
                phase = .errorDeviceCode(.network)
                return
            case let .success(token):
                await handleSuccess(token: token)
                return
            }
        }
    }

    private func handleSuccess(token: String) async {
        do {
            let user = try await service.fetchAuthenticatedUser(token: token)
            authState.completeSignIn(token: token, user: user)
            coordinator.popToRoot(of: .settings)
        } catch is CancellationError {
            return
        } catch {
            phase = .errorDeviceCode(.network)
        }
    }
}
