import Foundation

nonisolated struct RepositorySearchConditionSnapshot: Sendable, Hashable, Codable {
    let qualifiers: RepositorySearchQualifiers
    let sort: RepositorySearchSort

    private enum CodingKeys: String, CodingKey {
        case qualifiers
        case sort
    }

    init(qualifiers: RepositorySearchQualifiers, sort: RepositorySearchSort) {
        self.qualifiers = qualifiers
        self.sort = sort
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.qualifiers = try container.decode(RepositorySearchQualifiers.self, forKey: .qualifiers)
        if let decodedSort = try? container.decode(RepositorySearchSort.self, forKey: .sort) {
            self.sort = decodedSort
        } else {
            _ = try container.decode(EmptyObject.self, forKey: .sort)
            self.sort = .default
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(qualifiers, forKey: .qualifiers)
        try container.encode(sort, forKey: .sort)
    }
}

private struct EmptyObject: Decodable {
    init(from decoder: any Decoder) throws {
        _ = try decoder.container(keyedBy: AnyKey.self)
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        let intValue: Int? = nil
        init?(intValue: Int) { return nil }
    }
}

extension RepositorySearchQualifiers: Codable {
    private enum CodingKeys: String, CodingKey {
        case inTargets
        case language
        case stars
        case pushed
        case topics
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawInTargets = try container.decode([String].self, forKey: .inTargets)
        let parsedInTargets = rawInTargets.compactMap(RepositorySearchInTarget.init(rawValue:))
        self.inTargets = Set(parsedInTargets)

        let languageName = try container.decodeIfPresent(String.self, forKey: .language)
        if let languageName, GitHubLanguage.all.contains(where: { $0.name == languageName }) {
            self.language = GitHubLanguage(name: languageName)
        } else {
            self.language = nil
        }

        self.stars = try container.decode(RepositorySearchStarsRange.self, forKey: .stars)
        self.pushed = try container.decode(RepositorySearchPushedRange.self, forKey: .pushed)
        self.topics = try container.decode([String].self, forKey: .topics)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let orderedInTargets = RepositorySearchQualifiers.inTargetOrder
            .filter { inTargets.contains($0) }
            .map(\.rawValue)
        try container.encode(orderedInTargets, forKey: .inTargets)
        try container.encodeIfPresent(language?.name, forKey: .language)
        try container.encode(stars, forKey: .stars)
        try container.encode(pushed, forKey: .pushed)
        try container.encode(topics, forKey: .topics)
    }
}

extension RepositorySearchStarsRange: Codable {
    private enum CodingKeys: String, CodingKey {
        case min
        case max
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let min = try container.decodeIfPresent(Int.self, forKey: .min)
        let max = try container.decodeIfPresent(Int.self, forKey: .max)
        self.init(min: min, max: max)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(min, forKey: .min)
        try container.encodeIfPresent(max, forKey: .max)
    }
}

extension RepositorySearchPushedRange: Codable {
    private enum CodingKeys: String, CodingKey {
        case from
        case to
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let from = try container.decodeIfPresent(String.self, forKey: .from)
        let to = try container.decodeIfPresent(String.self, forKey: .to)
        self.init(from: from, to: to)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
    }
}

extension RepositorySearchSort: Codable {
    private enum CodingKeys: String, CodingKey {
        case key
        case order
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyRaw = try container.decode(String.self, forKey: .key)
        let orderRaw = try container.decode(String.self, forKey: .order)
        guard
            let parsedKey = RepositorySearchSortKey(rawValue: keyRaw),
            let parsedOrder = RepositorySearchSortOrder(rawValue: orderRaw)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .key,
                in: container,
                debugDescription: "Unknown sort key or order"
            )
        }
        self.init(key: parsedKey, order: parsedOrder)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key.rawValue, forKey: .key)
        try container.encode(order.rawValue, forKey: .order)
    }
}
