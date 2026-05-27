import Foundation

nonisolated extension GitHubRepoDetail {
    static let sampleSwift = GitHubRepoDetail(
        fullName: GitHubRepoFullName(ownerLogin: "apple", name: "swift"),
        owner: .sampleApple,
        description: "The Swift Programming Language",
        // swiftlint:disable:next force_unwrapping
        htmlUrl: URL(string: "https://github.com/apple/swift")!,
        stargazersCount: 67000,
        watchersCount: 67000,
        forksCount: 10300,
        openIssuesCount: 7500,
        language: "C++",
        topics: ["swift", "compiler", "programming-language"],
        defaultBranch: "main",
        // swiftlint:disable:next force_unwrapping
        createdAt: ISO8601DateFormatter().date(from: "2014-11-18T00:00:00Z")!,
        // swiftlint:disable:next force_unwrapping
        updatedAt: ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!
    )

    static let sampleAlamofire = GitHubRepoDetail(
        fullName: GitHubRepoFullName(ownerLogin: "Alamofire", name: "Alamofire"),
        owner: .sampleAlamofireOrg,
        description: "Elegant HTTP Networking in Swift",
        // swiftlint:disable:next force_unwrapping
        htmlUrl: URL(string: "https://github.com/Alamofire/Alamofire")!,
        stargazersCount: 41000,
        watchersCount: 41000,
        forksCount: 7500,
        openIssuesCount: 30,
        language: "Swift",
        topics: ["swift", "networking", "ios"],
        defaultBranch: "master",
        // swiftlint:disable:next force_unwrapping
        createdAt: ISO8601DateFormatter().date(from: "2014-05-20T00:00:00Z")!,
        // swiftlint:disable:next force_unwrapping
        updatedAt: ISO8601DateFormatter().date(from: "2026-04-15T00:00:00Z")!
    )
}
