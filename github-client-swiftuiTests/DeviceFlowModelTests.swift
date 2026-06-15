import Foundation
import Testing
import os
@testable import github_client_swiftui

@MainActor
struct DeviceFlowModelTests {

    private func makeSUT(
        deviceCodeResult: Result<GitHubDeviceCode, Error> = .success(
            GitHubDeviceCode(
                deviceCode: "DC",
                userCode: "WDJB-MJHT",
                verificationURL: URL(string: "https://github.com/login/device")!,
                expiresIn: 900,
                interval: 1
            )
        ),
        userResult: Result<GitHubAuthenticatedUser, Error> = .success(.sample),
        clientID: String? = "ci"
    ) -> (model: DeviceFlowModel, mock: MockGitHubAuthService, authState: GitHubAuthState, coordinator: AppCoordinator) {
        let mock = MockGitHubAuthService(
            deviceCodeResult: deviceCodeResult,
            userResult: userResult,
            clientIDValue: clientID
        )
        let authState = GitHubAuthState(service: mock, profileCache: nil)
        let coordinator = AppCoordinator()
        let model = DeviceFlowModel(
            service: mock,
            authState: authState,
            coordinator: coordinator,
            intervalScale: 0.0
        )
        return (model, mock, authState, coordinator)
    }

    private func waitForInflight(_ model: DeviceFlowModel) async {
        await model.inFlightTask?.value
    }

    // MARK: - device code 取得成功 / 失敗

    @Test func start_success_transitionsToPolling() async {
        let (model, mock, _, _) = makeSUT()
        mock.setPollHandler { _ in .pending }
        model.start()
        await Task.yield()
        defer { model.cancel() }

        if case let .polling(code) = model.phase {
            #expect(code.userCode == "WDJB-MJHT")
        } else {
            Issue.record("Expected polling phase, got \(model.phase)")
        }
    }

    @Test func start_deviceCodeNetworkFailure_showsErrorDeviceCode_network() async {
        let (model, _, _, _) = makeSUT(deviceCodeResult: .failure(URLError(.notConnectedToInternet)))
        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorDeviceCode(.network))
    }

    @Test func start_emptyClientID_showsErrorDeviceCode_config() async {
        let (model, _, _, _) = makeSUT(clientID: "")
        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorDeviceCode(.config))
    }

    // MARK: - polling 応答

    @Test func polling_accessDenied_transitionsToErrorAccessDenied() async {
        let (model, mock, _, _) = makeSUT()
        mock.setPollHandler { _ in .accessDenied }

        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorAccessDenied)
    }

    @Test func polling_expiredToken_transitionsToErrorExpired() async {
        let (model, mock, _, _) = makeSUT()
        mock.setPollHandler { _ in .expiredToken }

        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorExpired)
    }

    @Test func polling_success_completesSignIn() async {
        let (model, mock, authState, _) = makeSUT()
        mock.setPollHandler { _ in .success(accessToken: "gho_xxx") }

        model.start()
        await waitForInflight(model)

        #expect(authState.phase == .signedIn)
        #expect(authState.token == "gho_xxx")
        #expect(authState.user == .sample)
    }

    @Test func polling_pendingThenSuccess_eventuallySignsIn() async {
        let (model, mock, authState, _) = makeSUT()
        let lock = OSAllocatedUnfairLock<Int>(initialState: 0)
        mock.setPollHandler { _ in
            let count = lock.withLock { state -> Int in
                state += 1
                return state
            }
            if count < 3 {
                return .pending
            } else {
                return .success(accessToken: "gho_yyy")
            }
        }

        model.start()
        await waitForInflight(model)
        #expect(authState.phase == .signedIn)
        #expect(authState.token == "gho_yyy")
        #expect(mock.pollCallCount == 3)
    }

    @Test func polling_slowDown_increasesIntervalThenSucceeds() async {
        let (model, mock, authState, _) = makeSUT()
        let lock = OSAllocatedUnfairLock<Int>(initialState: 0)
        mock.setPollHandler { _ in
            let count = lock.withLock { state -> Int in
                state += 1
                return state
            }
            if count == 1 { return .slowDown }
            return .success(accessToken: "gho_z")
        }

        model.start()
        await waitForInflight(model)
        #expect(authState.phase == .signedIn)
        #expect(mock.pollCallCount == 2)
    }

    @Test func polling_networkFailure_continuesPolling() async {
        let (model, mock, authState, _) = makeSUT()
        let lock = OSAllocatedUnfairLock<Int>(initialState: 0)
        mock.setPollHandler { _ in
            let count = lock.withLock { state -> Int in
                state += 1
                return state
            }
            if count < 3 {
                throw URLError(.notConnectedToInternet)
            }
            return .success(accessToken: "gho_n")
        }

        model.start()
        await waitForInflight(model)
        #expect(authState.phase == .signedIn)
        #expect(mock.pollCallCount == 3)
    }

    // MARK: - cancel / restart

    @Test func cancel_duringPolling_stopsLoop_withoutSigningIn() async {
        let (model, mock, authState, _) = makeSUT()
        mock.setPollHandler { _ in .pending }
        model.start()
        await Task.yield()
        model.cancel()
        await waitForInflight(model)

        #expect(authState.phase == .signedOut)
    }

    @Test func restart_afterExpired_resetsToLoading_andPollAgain() async {
        let (model, mock, authState, _) = makeSUT()
        mock.setPollHandler { _ in .expiredToken }

        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorExpired)

        mock.setPollHandler { _ in .success(accessToken: "gho_r") }
        model.restart()
        await model.inFlightTask?.value
        #expect(authState.phase == .signedIn)
        #expect(authState.token == "gho_r")
    }

    @Test func polling_userFetchFailure_setsErrorDeviceCodeNetwork() async {
        let (model, mock, authState, _) = makeSUT(userResult: .failure(URLError(.notConnectedToInternet)))
        mock.setPollHandler { _ in .success(accessToken: "gho_u") }

        model.start()
        await waitForInflight(model)
        #expect(authState.phase == .signedOut)
        #expect(model.phase == .errorDeviceCode(.network))
    }
}

