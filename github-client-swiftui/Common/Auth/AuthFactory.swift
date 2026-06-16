import Foundation
import Observation

@Observable
final class AuthFactory {
    let repository: GitHubAuthRepositoryProtocol

    init(repository: GitHubAuthRepositoryProtocol) {
        self.repository = repository
    }

    func makeDeviceFlowModel(
        authState: GitHubAuthState,
        coordinator: AppCoordinator
    ) -> DeviceFlowModel {
        DeviceFlowModel(repository: repository, authState: authState, coordinator: coordinator)
    }
}
