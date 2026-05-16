import Foundation

nonisolated enum RepositorySearchError: Error, Equatable, Sendable {
    case network
    case rateLimited(resetDate: Date?)
}

nonisolated enum RepositorySearchErrorMapper {
    static func map(_ error: Error) -> RepositorySearchError? {
        if error is CancellationError { return nil }

        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return nil }
            return .network
        }

        if let httpError = error as? HttpClientError {
            switch httpError {
            case let .httpError(statusCode, _, headers):
                if statusCode == 429 {
                    return .rateLimited(resetDate: parseResetDate(headers))
                }
                if statusCode == 403, isRateLimited(headers) {
                    return .rateLimited(resetDate: parseResetDate(headers))
                }
                if (500...599).contains(statusCode) {
                    return .network
                }
                return .network
            case .networkError, .invalidURL, .decodingError:
                return .network
            }
        }

        return .network
    }

    private static func isRateLimited(_ headers: [String: String]) -> Bool {
        guard let remaining = headerValue(headers, name: "X-RateLimit-Remaining") else { return false }
        return Int(remaining) == 0
    }

    private static func parseResetDate(_ headers: [String: String]) -> Date? {
        guard let value = headerValue(headers, name: "X-RateLimit-Reset"),
              let seconds = TimeInterval(value)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func headerValue(_ headers: [String: String], name: String) -> String? {
        if let exact = headers[name] { return exact }
        let lowered = name.lowercased()
        for (key, value) in headers where key.lowercased() == lowered {
            return value
        }
        return nil
    }
}
