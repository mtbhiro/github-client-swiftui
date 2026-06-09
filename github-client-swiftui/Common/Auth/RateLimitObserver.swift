import Foundation
import Observation
import os

nonisolated enum RateLimitResource: String, Equatable {
    case core
    case search
}

struct RateLimitSnapshot: Equatable, Sendable {
    let limit: Int
    let remaining: Int
}

@Observable
final class RateLimitObserver {
    private(set) var snapshots: [RateLimitResource: RateLimitSnapshot] = [:]

    var snapshot: RateLimitSnapshot? {
        snapshots[.core] ?? snapshots[.search]
    }

    func update(from headers: [String: String]) {
        guard
            let limitString = headers["x-ratelimit-limit"],
            let remainingString = headers["x-ratelimit-remaining"],
            let limit = Int(limitString),
            let remaining = Int(remainingString)
        else {
            return
        }
        let resource: RateLimitResource
        if let raw = headers["x-ratelimit-resource"] {
            resource = RateLimitResource(rawValue: raw) ?? .core
        } else {
            resource = .core
        }
        snapshots[resource] = RateLimitSnapshot(limit: limit, remaining: remaining)
        if remaining <= 10 {
            Logger.rateLimit.warning("Rate limit low (\(resource.rawValue)): \(remaining)/\(limit)")
        }
    }

    func reset() {
        snapshots = [:]
    }
}
