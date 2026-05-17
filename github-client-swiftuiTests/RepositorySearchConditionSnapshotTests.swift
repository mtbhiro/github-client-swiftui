import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchConditionSnapshotTests {

    private func encode(_ snapshot: RepositorySearchConditionSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    private func decode(_ data: Data) throws -> RepositorySearchConditionSnapshot {
        try JSONDecoder().decode(RepositorySearchConditionSnapshot.self, from: data)
    }

    // MARK: - 単純な round-trip

    @Test func roundTrip_preservesAllFields() throws {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [.name, .description],
            language: GitHubLanguage(name: "Swift"),
            stars: .init(min: 100, max: 5000),
            pushed: .init(from: "2025-01-01", to: "2025-12-31"),
            topics: ["ios", "swiftui"]
        )
        let sort = RepositorySearchSort(key: .updated, order: .asc)
        let snapshot = RepositorySearchConditionSnapshot(qualifiers: qualifiers, sort: sort)

        let restored = try decode(try encode(snapshot))

        #expect(restored.qualifiers == qualifiers)
        #expect(restored.sort == sort)
    }

    @Test func roundTrip_emptyQualifiersAndDefaultSort() throws {
        let snapshot = RepositorySearchConditionSnapshot(
            qualifiers: .empty,
            sort: .default
        )

        let restored = try decode(try encode(snapshot))

        #expect(restored.qualifiers == .empty)
        #expect(restored.sort == .default)
    }

    // MARK: - 縮退ルール (AC-4.3)

    @Test func unknownLanguage_isReducedToNil_otherFieldsPreserved() throws {
        let json = """
        {
          "qualifiers": {
            "inTargets": ["name"],
            "language": "ThisLanguageDoesNotExist",
            "stars": {"min": 10, "max": 20},
            "pushed": {"from": "2025-01-01", "to": null},
            "topics": ["a"]
          },
          "sort": {"key": "stars", "order": "desc"}
        }
        """.data(using: .utf8)!

        let restored = try decode(json)

        #expect(restored.qualifiers.language == nil)
        #expect(restored.qualifiers.inTargets == [.name])
        #expect(restored.qualifiers.stars.min == 10)
        #expect(restored.qualifiers.stars.max == 20)
        #expect(restored.qualifiers.pushed.from == "2025-01-01")
        #expect(restored.qualifiers.pushed.to == nil)
        #expect(restored.qualifiers.topics == ["a"])
        #expect(restored.sort == .default)
    }

    @Test func unknownSortKey_isReducedToDefault_qualifiersPreserved() throws {
        let json = """
        {
          "qualifiers": {
            "inTargets": [],
            "language": "Swift",
            "stars": {"min": null, "max": null},
            "pushed": {"from": null, "to": null},
            "topics": []
          },
          "sort": {"key": "forks", "order": "desc"}
        }
        """.data(using: .utf8)!

        let restored = try decode(json)

        #expect(restored.qualifiers.language == GitHubLanguage(name: "Swift"))
        #expect(restored.sort == .default)
    }

    @Test func unknownSortOrder_isReducedToDefault() throws {
        let json = """
        {
          "qualifiers": {
            "inTargets": [],
            "language": null,
            "stars": {"min": null, "max": null},
            "pushed": {"from": null, "to": null},
            "topics": []
          },
          "sort": {"key": "stars", "order": "sideways"}
        }
        """.data(using: .utf8)!

        let restored = try decode(json)

        #expect(restored.sort == .default)
    }

    @Test func unknownInTargets_areDropped_knownPreserved() throws {
        let json = """
        {
          "qualifiers": {
            "inTargets": ["name", "totally-unknown", "readme"],
            "language": null,
            "stars": {"min": null, "max": null},
            "pushed": {"from": null, "to": null},
            "topics": []
          },
          "sort": {"key": "stars", "order": "desc"}
        }
        """.data(using: .utf8)!

        let restored = try decode(json)

        #expect(restored.qualifiers.inTargets == [.name, .readme])
    }

    // MARK: - 構造破損 (AC-4.1: 全体無視)

    @Test func missingQualifiersRoot_throwsDecodingError() {
        let json = """
        { "sort": {"key": "stars", "order": "desc"} }
        """.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try decode(json)
        }
    }

    @Test func missingSortRoot_throwsDecodingError() {
        let json = """
        {
          "qualifiers": {
            "inTargets": [],
            "language": null,
            "stars": {"min": null, "max": null},
            "pushed": {"from": null, "to": null},
            "topics": []
          }
        }
        """.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try decode(json)
        }
    }

    @Test func invalidJSON_throws() {
        let json = Data("not a json".utf8)
        #expect(throws: (any Error).self) {
            try decode(json)
        }
    }
}
