import Foundation
import Observation
import os

struct RateLimitSnapshot: Equatable, Sendable {
    let limit: Int
    let remaining: Int
}

@Observable
final class RateLimitObserver {
    private(set) var snapshot: RateLimitSnapshot?

    func update(from headers: [String: String]) {
        guard
            let limitString = headers["x-ratelimit-limit"],
            let remainingString = headers["x-ratelimit-remaining"],
            let limit = Int(limitString),
            let remaining = Int(remainingString)
        else {
            return
        }
        snapshot = RateLimitSnapshot(limit: limit, remaining: remaining)
        if remaining <= 10 {
            Logger.rateLimit.warning("Rate limit low: \(remaining)/\(limit)")
        }
    }

    func reset() {
        snapshot = nil
    }
}
