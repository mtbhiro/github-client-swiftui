import Foundation

nonisolated enum RepositorySearchQueryBuilder {
    static func build(keyword: String, qualifiers: RepositorySearchQualifiers) -> String {
        var parts: [String] = []

        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            parts.append(quoteIfNeeded(trimmedKeyword))
        }

        if !qualifiers.inTargets.isEmpty {
            let ordered = RepositorySearchQualifiers.inTargetOrder.filter { qualifiers.inTargets.contains($0) }
            let value = ordered.map(\.rawValue).joined(separator: ",")
            parts.append("in:\(value)")
        }

        if let language = qualifiers.language {
            parts.append("language:\(quoteIfNeeded(language.name))")
        }

        if let starsValue = serializeStars(qualifiers.stars) {
            parts.append(starsValue)
        }

        if let pushedValue = serializePushed(qualifiers.pushed) {
            parts.append(pushedValue)
        }

        for topic in qualifiers.topics {
            let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            parts.append("topic:\(trimmed)")
        }

        return parts.joined(separator: " ")
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        value.contains(" ") ? "\"\(value)\"" : value
    }

    private static func serializeStars(_ stars: RepositorySearchStarsRange) -> String? {
        guard stars.isValid, !stars.isEmpty else { return nil }
        switch (stars.min, stars.max) {
        case let (min?, max?):
            return "stars:\(min)..\(max)"
        case let (min?, .none):
            return "stars:>=\(min)"
        case let (.none, max?):
            return "stars:<=\(max)"
        case (.none, .none):
            return nil
        }
    }

    private static func serializePushed(_ pushed: RepositorySearchPushedRange) -> String? {
        guard pushed.isValid, !pushed.isEmpty else { return nil }
        switch (pushed.from, pushed.to) {
        case let (from?, to?):
            return "pushed:\(from)..\(to)"
        case let (from?, .none):
            return "pushed:>=\(from)"
        case let (.none, to?):
            return "pushed:<=\(to)"
        case (.none, .none):
            return nil
        }
    }
}
