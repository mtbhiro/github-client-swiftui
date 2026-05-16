import Foundation

nonisolated enum RepositorySearchSortKey: String, Sendable, Hashable, CaseIterable, Identifiable {
    case stars
    case updated

    var id: String { rawValue }
}

nonisolated enum RepositorySearchSortOrder: String, Sendable, Hashable, CaseIterable, Identifiable {
    case asc
    case desc

    var id: String { rawValue }
}

nonisolated struct RepositorySearchSort: Sendable, Hashable {
    var key: RepositorySearchSortKey
    var order: RepositorySearchSortOrder

    static let `default` = RepositorySearchSort(key: .stars, order: .desc)
}
