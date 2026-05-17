import Foundation

nonisolated final class RepositorySearchConditionStore {
    static let storageKey = "repositorySearchCondition"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RepositorySearchConditionSnapshot? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        do {
            return try JSONDecoder().decode(RepositorySearchConditionSnapshot.self, from: data)
        } catch {
            defaults.removeObject(forKey: Self.storageKey)
            return nil
        }
    }

    func save(_ snapshot: RepositorySearchConditionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
