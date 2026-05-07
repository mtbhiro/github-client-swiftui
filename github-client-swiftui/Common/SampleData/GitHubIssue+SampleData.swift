import Foundation

nonisolated extension GitHubUser {
    static let sampleOctocat = GitHubUser(
        login: "octocat",
        id: 1,
        avatarUrl: URL(string: "https://avatars.githubusercontent.com/u/583231?v=4"),
        htmlUrl: URL(string: "https://github.com/octocat")!
    )

    static let sampleDeveloper = GitHubUser(
        login: "swift-dev",
        id: 12345,
        avatarUrl: URL(string: "https://avatars.githubusercontent.com/u/12345?v=4"),
        htmlUrl: URL(string: "https://github.com/swift-dev")!
    )
}

nonisolated extension GitHubLabel {
    static let sampleBug = GitHubLabel(id: 1, name: "bug", color: "d73a4a")
    static let sampleEnhancement = GitHubLabel(id: 2, name: "enhancement", color: "a2eeef")
    static let sampleDocumentation = GitHubLabel(id: 3, name: "documentation", color: "0075ca")
}

nonisolated extension GitHubIssue {
    static let sampleOpen = GitHubIssue(
        id: 1001,
        number: 42,
        title: "Swift 6 strict concurrency でのコンパイルエラー",
        state: .open,
        user: .sampleOctocat,
        labels: [.sampleBug],
        commentsCount: 5,
        createdAt: ISO8601DateFormatter().date(from: "2026-04-20T10:00:00Z")!,
        isPullRequest: false
    )

    static let sampleClosed = GitHubIssue(
        id: 1002,
        number: 38,
        title: "README にインストール手順を追加",
        state: .closed,
        user: .sampleDeveloper,
        labels: [.sampleDocumentation],
        commentsCount: 2,
        createdAt: ISO8601DateFormatter().date(from: "2026-04-10T08:30:00Z")!,
        isPullRequest: false
    )

    static let samplePullRequest = GitHubIssue(
        id: 1003,
        number: 45,
        title: "async/await への移行",
        state: .open,
        user: .sampleDeveloper,
        labels: [.sampleEnhancement],
        commentsCount: 12,
        createdAt: ISO8601DateFormatter().date(from: "2026-04-25T14:00:00Z")!,
        isPullRequest: true
    )

    static let samples: [GitHubIssue] = [sampleOpen, sampleClosed, samplePullRequest]
}

nonisolated extension GitHubIssueDetail {
    static let sample = GitHubIssueDetail(
        id: 1001,
        number: 42,
        title: "Swift 6 strict concurrency でのコンパイルエラー",
        body: """
        ## 概要
        Swift 6 の strict concurrency チェックを有効にすると、以下の箇所でコンパイルエラーが発生します。

        ## 再現手順
        1. `SWIFT_STRICT_CONCURRENCY=complete` を設定
        2. ビルドを実行

        ## 期待する動作
        コンパイルエラーなしでビルドが成功すること。
        """,
        state: .open,
        user: .sampleOctocat,
        labels: [.sampleBug],
        commentsCount: 5,
        htmlUrl: URL(string: "https://github.com/apple/swift/issues/42")!,
        createdAt: ISO8601DateFormatter().date(from: "2026-04-20T10:00:00Z")!,
        updatedAt: ISO8601DateFormatter().date(from: "2026-05-01T15:30:00Z")!
    )
}

nonisolated extension GitHubIssueComment {
    static let sampleFirst = GitHubIssueComment(
        id: 2001,
        user: .sampleDeveloper,
        body: "こちらの Issue を確認しました。修正PRを作成中です。",
        createdAt: ISO8601DateFormatter().date(from: "2026-04-21T09:00:00Z")!
    )

    static let sampleSecond = GitHubIssueComment(
        id: 2002,
        user: .sampleOctocat,
        body: "ありがとうございます！関連する Issue として #38 も参照してください。\n\n`@MainActor` の隔離が必要なケースが他にもあるかもしれません。",
        createdAt: ISO8601DateFormatter().date(from: "2026-04-21T11:30:00Z")!
    )

    static let samples: [GitHubIssueComment] = [sampleFirst, sampleSecond]
}
