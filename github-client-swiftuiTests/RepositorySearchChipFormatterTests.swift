import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchChipFormatterTests {

    @Test func keyword_isWrappedInDoubleQuotes() {
        let chips = RepositorySearchChipFormatter.chips(keyword: "swiftui", qualifiers: .empty)
        #expect(chips.contains(.keyword(label: "\"swiftui\"")))
    }

    @Test func emptyKeyword_noKeywordChip() {
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: .empty)
        #expect(!chips.contains(where: { if case .keyword = $0 { return true } else { return false } }))
    }

    @Test func inTargets_multi_singleChipInFixedOrder() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [.description, .name],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.inTargets(label: "in: name, description")))
    }

    @Test func language_plainLabel_noQuotes() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: GitHubLanguage(name: "Vim Script"),
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.language(label: "Vim Script")))
    }

    @Test func stars_minOnly_labelFormat() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: 100, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.stars(label: "★ ≥ 100")))
    }

    @Test func stars_maxOnly_labelFormat() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: 5000),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.stars(label: "★ ≤ 5000")))
    }

    @Test func stars_range_labelFormat() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: 100, max: 5000),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.stars(label: "★ 100–5000")))
    }

    @Test func pushed_fromOnly_labelFormat() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: "2025-01-01", to: nil),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.pushed(label: "pushed: ≥ 2025-01-01")))
    }

    @Test func pushed_toOnly_labelFormat() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: "2025-12-31"),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.pushed(label: "pushed: ≤ 2025-12-31")))
    }

    @Test func pushed_range_labelFormat() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: "2025-01-01", to: "2025-12-31"),
            topics: []
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.pushed(label: "pushed: 2025-01-01 – 2025-12-31")))
    }

    @Test func topics_multiple_individualChipsInOrder() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: ["ios", "swiftui"]
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "", qualifiers: qualifiers)
        #expect(chips.contains(.topic(label: "#ios", value: "ios")))
        #expect(chips.contains(.topic(label: "#swiftui", value: "swiftui")))
    }

    @Test func chipOrder_followsFixedQualifierOrder() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [.name],
            language: GitHubLanguage(name: "Swift"),
            stars: .init(min: 100, max: nil),
            pushed: .init(from: "2025-01-01", to: nil),
            topics: ["ios", "swiftui"]
        )
        let chips = RepositorySearchChipFormatter.chips(keyword: "ui", qualifiers: qualifiers)
        #expect(chips == [
            .keyword(label: "\"ui\""),
            .inTargets(label: "in: name"),
            .language(label: "Swift"),
            .stars(label: "★ ≥ 100"),
            .pushed(label: "pushed: ≥ 2025-01-01"),
            .topic(label: "#ios", value: "ios"),
            .topic(label: "#swiftui", value: "swiftui"),
        ])
    }
}
