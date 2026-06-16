import Foundation
import Observation

/// View 層から DeviceFlow / Settings 等の Model を組み立てるためのファクトリ。
/// `@Observable` 化することで `Environment` 経由で View に流せるが、内部状態は持たない。
/// `service` への参照は DeviceFlowModel 等の Model を組み立てるために必要なため、ここに集約する。
@Observable
final class AuthFactory {
    let service: GitHubAuthServiceProtocol

    init(service: GitHubAuthServiceProtocol) {
        self.service = service
    }

    func makeDeviceFlowModel(
        authState: GitHubAuthState,
        coordinator: AppCoordinator
    ) -> DeviceFlowModel {
        DeviceFlowModel(service: service, authState: authState, coordinator: coordinator)
    }
}
