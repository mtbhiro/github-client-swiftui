import Foundation

nonisolated enum RepositorySearchInTarget: String, Sendable, Hashable, CaseIterable, Identifiable {
    case name
    case description
    case readme
    case topics

    var id: String { rawValue }
}

nonisolated struct RepositorySearchStarsRange: Sendable, Hashable {
    let min: Int?
    let max: Int?

    var isEmpty: Bool { min == nil && max == nil }

    var isValid: Bool {
        if let min, min < 0 { return false }
        if let max, max < 0 { return false }
        if let min, let max, min > max { return false }
        return true
    }
}

nonisolated struct RepositorySearchPushedRange: Sendable, Hashable {
    let from: String?
    let to: String?

    var isEmpty: Bool { from == nil && to == nil }

    var isValid: Bool {
        if let from, !Self.isISODate(from) { return false }
        if let to, !Self.isISODate(to) { return false }
        if let from, let to, from > to { return false }
        return true
    }

    private static func isISODate(_ value: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}-\d{2}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

nonisolated struct RepositorySearchQualifiers: Sendable, Hashable {
    var inTargets: Set<RepositorySearchInTarget>
    var language: GitHubLanguage?
    var stars: RepositorySearchStarsRange
    var pushed: RepositorySearchPushedRange
    var topics: [String]

    static let empty = RepositorySearchQualifiers(
        inTargets: [],
        language: nil,
        stars: .init(min: nil, max: nil),
        pushed: .init(from: nil, to: nil),
        topics: []
    )

    var isEmpty: Bool {
        inTargets.isEmpty
            && language == nil
            && stars.isEmpty
            && pushed.isEmpty
            && topics.isEmpty
    }

    var isValid: Bool {
        stars.isValid && pushed.isValid
    }

    static let inTargetOrder: [RepositorySearchInTarget] = [.name, .description, .readme, .topics]
}
