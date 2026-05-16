import Foundation

nonisolated enum RepositorySearchChip: Sendable, Hashable {
    case keyword(label: String)
    case inTargets(label: String)
    case language(label: String)
    case stars(label: String)
    case pushed(label: String)
    case topic(label: String, value: String)

    var label: String {
        switch self {
        case let .keyword(label),
             let .inTargets(label),
             let .language(label),
             let .stars(label),
             let .pushed(label):
            return label
        case let .topic(label, _):
            return label
        }
    }
}

nonisolated enum RepositorySearchChipFormatter {
    static func chips(keyword: String, qualifiers: RepositorySearchQualifiers) -> [RepositorySearchChip] {
        var result: [RepositorySearchChip] = []

        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            result.append(.keyword(label: "\"\(trimmedKeyword)\""))
        }

        if !qualifiers.inTargets.isEmpty {
            let ordered = RepositorySearchQualifiers.inTargetOrder.filter { qualifiers.inTargets.contains($0) }
            let value = ordered.map(\.rawValue).joined(separator: ", ")
            result.append(.inTargets(label: "in: \(value)"))
        }

        if let language = qualifiers.language {
            result.append(.language(label: language.name))
        }

        if let starsLabel = formatStars(qualifiers.stars) {
            result.append(.stars(label: starsLabel))
        }

        if let pushedLabel = formatPushed(qualifiers.pushed) {
            result.append(.pushed(label: pushedLabel))
        }

        for topic in qualifiers.topics {
            let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result.append(.topic(label: "#\(trimmed)", value: trimmed))
        }

        return result
    }

    private static func formatStars(_ stars: RepositorySearchStarsRange) -> String? {
        guard stars.isValid, !stars.isEmpty else { return nil }
        switch (stars.min, stars.max) {
        case let (min?, max?):
            return "★ \(min)–\(max)"
        case let (min?, .none):
            return "★ ≥ \(min)"
        case let (.none, max?):
            return "★ ≤ \(max)"
        case (.none, .none):
            return nil
        }
    }

    private static func formatPushed(_ pushed: RepositorySearchPushedRange) -> String? {
        guard pushed.isValid, !pushed.isEmpty else { return nil }
        switch (pushed.from, pushed.to) {
        case let (from?, to?):
            return "pushed: \(from) – \(to)"
        case let (from?, .none):
            return "pushed: ≥ \(from)"
        case let (.none, to?):
            return "pushed: ≤ \(to)"
        case (.none, .none):
            return nil
        }
    }
}
