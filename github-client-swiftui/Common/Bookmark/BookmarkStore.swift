import Foundation
import Observation

@MainActor
@Observable
final class BookmarkStore {
    private static let userDefaultsKey = "bookmarkItems"
    private let defaults: UserDefaults?

    private(set) var items: [BookmarkItem] = []

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let defaults {
            self.items = Self.load(from: defaults)
        }
    }

    init(items: [BookmarkItem]) {
        self.defaults = nil
        self.items = items
    }

    func add(_ item: BookmarkItem) {
        guard !contains(item) else { return }
        items.insert(item, at: 0)
        save()
    }

    func remove(_ item: BookmarkItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func toggle(_ item: BookmarkItem) {
        if contains(item) {
            remove(item)
        } else {
            add(item)
        }
    }

    func contains(_ item: BookmarkItem) -> Bool {
        items.contains { $0.id == item.id }
    }

    func repositories() -> [BookmarkItem] {
        items.filter { $0.isRepository }
    }

    func issues() -> [BookmarkItem] {
        items.filter { $0.isIssue }
    }

    private func save() {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> [BookmarkItem] {
        guard let data = defaults.data(forKey: userDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([BookmarkItem].self, from: data)) ?? []
    }
}
