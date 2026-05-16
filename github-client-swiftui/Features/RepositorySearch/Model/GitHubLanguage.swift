import Foundation

nonisolated struct GitHubLanguage: Sendable, Hashable, Identifiable {
    let name: String

    var id: String { name }
}

nonisolated extension GitHubLanguage {
    static let all: [GitHubLanguage] = [
        "Swift",
        "Objective-C",
        "Kotlin",
        "Java",
        "JavaScript",
        "TypeScript",
        "Python",
        "Ruby",
        "Go",
        "Rust",
        "C",
        "C++",
        "C#",
        "Dart",
        "PHP",
        "Scala",
        "Elixir",
        "Haskell",
        "Lua",
        "Perl",
        "R",
        "Shell",
        "PowerShell",
        "HTML",
        "CSS",
        "Vue",
        "Vim Script",
        "Erlang",
        "Clojure",
        "OCaml",
    ].map(GitHubLanguage.init(name:))
}
