import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchQueryBuilderTests {

    // MARK: - keyword only

    @Test func keywordOnly_becomesPlainKeyword() {
        let q = RepositorySearchQueryBuilder.build(keyword: "swiftui", qualifiers: .empty)
        #expect(q == "swiftui")
    }

    @Test func keywordWithSpace_isQuoted() {
        let q = RepositorySearchQueryBuilder.build(keyword: "swift ui", qualifiers: .empty)
        #expect(q == "\"swift ui\"")
    }

    @Test func keywordWithSurroundingWhitespace_isTrimmed() {
        let q = RepositorySearchQueryBuilder.build(keyword: "  swift  ", qualifiers: .empty)
        #expect(q == "swift")
    }

    @Test func emptyKeyword_isOmitted() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: GitHubLanguage(name: "Swift"),
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "", qualifiers: qualifiers)
        #expect(q == "language:Swift")
    }

    // MARK: - in:

    @Test func inTargets_serializeAsCommaSeparated_inFixedOrder() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [.description, .name],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x in:name,description")
    }

    @Test func inTargets_allFour_serializeInFixedOrder() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [.topics, .readme, .name, .description],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x in:name,description,readme,topics")
    }

    // MARK: - language:

    @Test func language_simpleName_unquoted() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: GitHubLanguage(name: "Swift"),
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x language:Swift")
    }

    @Test func language_withSpace_isQuoted() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: GitHubLanguage(name: "Vim Script"),
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x language:\"Vim Script\"")
    }

    // MARK: - stars:

    @Test func stars_minOnly_becomesGTE() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: 100, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x stars:>=100")
    }

    @Test func stars_maxOnly_becomesLTE() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: 5000),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x stars:<=5000")
    }

    @Test func stars_range_becomesDotDot() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: 100, max: 5000),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x stars:100..5000")
    }

    @Test func stars_invalidRange_isOmitted() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: 5000, max: 100),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x")
    }

    @Test func stars_negative_isOmitted() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: -1, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x")
    }

    // MARK: - pushed:

    @Test func pushed_fromOnly_becomesGTE() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: "2025-01-01", to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x pushed:>=2025-01-01")
    }

    @Test func pushed_toOnly_becomesLTE() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: "2025-12-31"),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x pushed:<=2025-12-31")
    }

    @Test func pushed_range_becomesDotDot() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: "2025-01-01", to: "2025-12-31"),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x pushed:2025-01-01..2025-12-31")
    }

    @Test func pushed_invalidRange_isOmitted() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: "2025-12-31", to: "2025-01-01"),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x")
    }

    @Test func pushed_invalidDateFormat_isOmitted() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: "2025/01/01", to: nil),
            topics: []
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x")
    }

    // MARK: - topic:

    @Test func topics_multiple_serializeAsSeparateQualifiers() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: ["ios", "swiftui"]
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x topic:ios topic:swiftui")
    }

    @Test func topics_blankEntries_areIgnored() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [],
            language: nil,
            stars: .init(min: nil, max: nil),
            pushed: .init(from: nil, to: nil),
            topics: ["  ", "ios", ""]
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "x", qualifiers: qualifiers)
        #expect(q == "x topic:ios")
    }

    // MARK: - 並び順固定

    @Test func qualifierOrder_isStable() {
        let qualifiers = RepositorySearchQualifiers(
            inTargets: [.name],
            language: GitHubLanguage(name: "Swift"),
            stars: .init(min: 100, max: 5000),
            pushed: .init(from: "2025-01-01", to: nil),
            topics: ["ios"]
        )
        let q = RepositorySearchQueryBuilder.build(keyword: "ui", qualifiers: qualifiers)
        #expect(q == "ui in:name language:Swift stars:100..5000 pushed:>=2025-01-01 topic:ios")
    }
}
