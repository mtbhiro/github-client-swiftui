import Foundation
import Observation

struct RateLimitSnapshot: Equatable, Sendable {
    let limit: Int
    let remaining: Int
}

@Observable
final class RateLimitObserver {
    private(set) var snapshot: RateLimitSnapshot?

    func update(from headers: [String: String]) {
        guard
            let limitString = headers["X-RateLimit-Limit"] ?? headers["x-ratelimit-limit"],
            let remainingString = headers["X-RateLimit-Remaining"] ?? headers["x-ratelimit-remaining"],
            let limit = Int(limitString),
            let remaining = Int(remainingString)
        else {
            return
        }
        snapshot = RateLimitSnapshot(limit: limit, remaining: remaining)
    }

    func reset() {
        snapshot = nil
    }
}
