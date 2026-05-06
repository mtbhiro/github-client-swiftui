import Foundation

extension GitHubRepository {
    static let sampleSwift = GitHubRepository(
        id: 44838949,
        name: "swift",
        fullName: "apple/swift",
        owner: .sampleApple,
        description: "The Swift Programming Language",
        htmlUrl: URL(string: "https://github.com/apple/swift")!,
        stargazersCount: 67000,
        forksCount: 10300,
        language: "C++",
        topics: ["swift", "compiler", "programming-language"]
    )

    static let sampleAlamofire = GitHubRepository(
        id: 15062869,
        name: "Alamofire",
        fullName: "Alamofire/Alamofire",
        owner: .sampleAlamofireOrg,
        description: "Elegant HTTP Networking in Swift",
        htmlUrl: URL(string: "https://github.com/Alamofire/Alamofire")!,
        stargazersCount: 41000,
        forksCount: 7500,
        language: "Swift",
        topics: ["swift", "networking", "ios"]
    )

    static let sampleVapor = GitHubRepository(
        id: 44965362,
        name: "vapor",
        fullName: "vapor/vapor",
        owner: .sampleVaporOrg,
        description: "A server-side Swift HTTP web framework.",
        htmlUrl: URL(string: "https://github.com/vapor/vapor")!,
        stargazersCount: 24000,
        forksCount: 1500,
        language: "Swift",
        topics: ["swift", "server", "web-framework"]
    )

    static let samples: [GitHubRepository] = [sampleSwift, sampleAlamofire, sampleVapor]
}

extension GitHubRepositoryOwner {
    static let sampleApple = GitHubRepositoryOwner(
        login: "apple",
        id: 10639145,
        avatarUrl: URL(string: "https://avatars.githubusercontent.com/u/10639145?v=4"),
        htmlUrl: URL(string: "https://github.com/apple")!
    )

    static let sampleAlamofireOrg = GitHubRepositoryOwner(
        login: "Alamofire",
        id: 7774181,
        avatarUrl: URL(string: "https://avatars.githubusercontent.com/u/7774181?v=4"),
        htmlUrl: URL(string: "https://github.com/Alamofire")!
    )

    static let sampleVaporOrg = GitHubRepositoryOwner(
        login: "vapor",
        id: 17364220,
        avatarUrl: URL(string: "https://avatars.githubusercontent.com/u/17364220?v=4"),
        htmlUrl: URL(string: "https://github.com/vapor")!
    )
}
