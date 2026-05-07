import Foundation

nonisolated extension GitHubRepoDetail {
    static let sampleSwift = GitHubRepoDetail(
        id: 44838949,
        name: "swift",
        fullName: "apple/swift",
        owner: .sampleApple,
        description: "The Swift Programming Language",
        htmlUrl: URL(string: "https://github.com/apple/swift")!,
        stargazersCount: 67000,
        watchersCount: 67000,
        forksCount: 10300,
        openIssuesCount: 7500,
        language: "C++",
        topics: ["swift", "compiler", "programming-language"],
        defaultBranch: "main",
        createdAt: ISO8601DateFormatter().date(from: "2014-11-18T00:00:00Z")!,
        updatedAt: ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!
    )

    static let sampleAlamofire = GitHubRepoDetail(
        id: 15062869,
        name: "Alamofire",
        fullName: "Alamofire/Alamofire",
        owner: .sampleAlamofireOrg,
        description: "Elegant HTTP Networking in Swift",
        htmlUrl: URL(string: "https://github.com/Alamofire/Alamofire")!,
        stargazersCount: 41000,
        watchersCount: 41000,
        forksCount: 7500,
        openIssuesCount: 30,
        language: "Swift",
        topics: ["swift", "networking", "ios"],
        defaultBranch: "master",
        createdAt: ISO8601DateFormatter().date(from: "2014-05-20T00:00:00Z")!,
        updatedAt: ISO8601DateFormatter().date(from: "2026-04-15T00:00:00Z")!
    )
}
