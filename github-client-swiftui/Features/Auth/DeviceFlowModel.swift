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
    private let repository: GitHubAuthRepositoryProtocol
    private let authState: GitHubAuthState
    private let coordinator: AppCoordinator
    private let intervalScale: Double

    init(
        repository: GitHubAuthRepositoryProtocol,
        authState: GitHubAuthState,
        coordinator: AppCoordinator,
        intervalScale: Double = 1.0
    ) {
        self.repository = repository
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
            code = try await repository.requestDeviceCode()
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
                outcome = try await repository.pollAccessToken(deviceCode: deviceCode.deviceCode)
            } catch is CancellationError {
                return
            } catch {
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
            let user = try await repository.fetchAuthenticatedUser(token: token)
            authState.completeSignIn(token: token, user: user)
            coordinator.popToRoot(of: .settings)
        } catch is CancellationError {
            return
        } catch {
            phase = .errorDeviceCode(.network)
        }
    }
}
