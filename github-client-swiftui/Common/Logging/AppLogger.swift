import os

extension Logger {
    nonisolated private static let subsystem = "hiroc19.github-client-swiftui"

    nonisolated static let auth = Logger(subsystem: subsystem, category: "auth")
    nonisolated static let network = Logger(subsystem: subsystem, category: "network")
    nonisolated static let rateLimit = Logger(subsystem: subsystem, category: "rateLimit")
    nonisolated static let cache = Logger(subsystem: subsystem, category: "cache")
}
