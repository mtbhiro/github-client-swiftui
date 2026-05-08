import Foundation
import Observation

@Observable
final class BookmarkStore {
    private let storage: UserDefaultsStorage<[BookmarkItem]>?

    private(set) var items: [BookmarkItem] = []

    init(defaults: UserDefaults? = .standard) {
        self.storage = defaults.map { UserDefaultsStorage(key: "bookmarkItems", defaults: $0) }
        self.items = storage?.load() ?? []
    }

    init(items: [BookmarkItem]) {
        self.storage = nil
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
        storage?.save(items)
    }
}
