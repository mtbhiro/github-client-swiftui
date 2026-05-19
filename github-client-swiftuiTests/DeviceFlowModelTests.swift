import Foundation
import Testing
import os
@testable import github_client_swiftui

@MainActor
struct DeviceFlowModelTests {

    private final class SignInRecorder: Sendable {
        private let lock = OSAllocatedUnfairLock<[(String, GitHubAuthenticatedUser)]>(initialState: [])
        var calls: [(String, GitHubAuthenticatedUser)] {
            lock.withLock { $0 }
        }
        nonisolated func record(_ token: String, _ user: GitHubAuthenticatedUser) {
            lock.withLock { $0.append((token, user)) }
        }
    }

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
    ) -> (model: DeviceFlowModel, mock: MockGitHubAuthService, recorder: SignInRecorder) {
        let mock = MockGitHubAuthService(
            deviceCodeResult: deviceCodeResult,
            userResult: userResult,
            clientIDValue: clientID
        )
        let recorder = SignInRecorder()
        let model = DeviceFlowModel(
            service: mock,
            intervalScale: 0.0,
            onSignInSuccess: { token, user in
                recorder.record(token, user)
            }
        )
        return (model, mock, recorder)
    }

    private func waitForInflight(_ model: DeviceFlowModel) async {
        await model.inFlightTask?.value
    }

    // MARK: - device code 取得成功 / 失敗

    @Test func start_success_transitionsToPolling() async {
        let (model, mock, _) = makeSUT()
        // poll はずっと pending を返し続ける状態にする
        mock.setPollHandler { _ in .pending }
        model.start()
        // 「polling に入っていること」を確認するには time を進める必要がある
        // intervalScale=0 のため Task.sleep は即抜け、loop に入る前の最後の `await` は requestDeviceCode 後の
        // `phase = .polling(code)` 直後。1 回 yield して MainActor 上で phase 更新を反映させる。
        try? await Task.sleep(for: .milliseconds(20))
        defer { model.cancel() }

        if case let .polling(code) = model.phase {
            #expect(code.userCode == "WDJB-MJHT")
        } else {
            Issue.record("Expected polling phase, got \(model.phase)")
        }
    }

    @Test func start_deviceCodeNetworkFailure_showsErrorDeviceCode_network() async {
        let (model, _, _) = makeSUT(deviceCodeResult: .failure(URLError(.notConnectedToInternet)))
        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorDeviceCode(.network))
    }

    @Test func start_emptyClientID_showsErrorDeviceCode_config() async {
        let (model, _, _) = makeSUT(clientID: "")
        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorDeviceCode(.config))
    }

    // MARK: - polling 応答

    @Test func polling_accessDenied_transitionsToErrorAccessDenied() async {
        let (model, mock, _) = makeSUT()
        mock.setPollHandler { _ in .accessDenied }

        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorAccessDenied)
    }

    @Test func polling_expiredToken_transitionsToErrorExpired() async {
        let (model, mock, _) = makeSUT()
        mock.setPollHandler { _ in .expiredToken }

        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorExpired)
    }

    @Test func polling_success_invokesOnSignInSuccess() async {
        let (model, mock, recorder) = makeSUT()
        mock.setPollHandler { _ in .success(accessToken: "gho_xxx") }

        model.start()
        await waitForInflight(model)

        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first?.0 == "gho_xxx")
        #expect(recorder.calls.first?.1 == .sample)
    }

    @Test func polling_pendingThenSuccess_eventuallySignsIn() async {
        let (model, mock, recorder) = makeSUT()
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
        #expect(recorder.calls.count == 1)
        #expect(mock.pollCallCount == 3)
    }

    @Test func polling_slowDown_increasesIntervalThenSucceeds() async {
        let (model, mock, recorder) = makeSUT()
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
        #expect(recorder.calls.count == 1)
        #expect(mock.pollCallCount == 2)
    }

    @Test func polling_networkFailure_continuesPolling() async {
        let (model, mock, recorder) = makeSUT()
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
        #expect(recorder.calls.count == 1)
        #expect(mock.pollCallCount == 3)
    }

    // MARK: - cancel / restart

    @Test func cancel_duringPolling_stopsLoop_withoutInvokingCallback() async {
        let (model, mock, recorder) = makeSUT()
        mock.setPollHandler { _ in
            // polling を継続させるため pending を返し続ける
            .pending
        }
        model.start()
        // polling に入ってから cancel する
        try? await Task.sleep(for: .milliseconds(20))
        model.cancel()
        await waitForInflight(model)

        #expect(recorder.calls.isEmpty)
    }

    @Test func restart_afterExpired_resetsToLoading_andPollAgain() async {
        let (model, mock, _) = makeSUT()
        mock.setPollHandler { _ in .expiredToken }

        model.start()
        await waitForInflight(model)
        #expect(model.phase == .errorExpired)

        mock.setPollHandler { _ in .success(accessToken: "gho_r") }
        model.restart()
        await waitForInflight(model)
        if case .polling = model.phase {
            Issue.record("Should have advanced past polling")
        }
    }

    @Test func polling_userFetchFailure_setsErrorDeviceCodeNetwork() async {
        let (model, mock, recorder) = makeSUT(userResult: .failure(URLError(.notConnectedToInternet)))
        mock.setPollHandler { _ in .success(accessToken: "gho_u") }

        model.start()
        await waitForInflight(model)
        #expect(recorder.calls.isEmpty)
        #expect(model.phase == .errorDeviceCode(.network))
    }
}

