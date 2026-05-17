import Foundation

nonisolated enum RepositorySearchError: Error, Equatable, Sendable {
    case network
    case rateLimited(resetDate: Date?)
}

nonisolated enum RepositorySearchErrorMapper {
    /// 取得時のエラーを UI 用のエラー種別にマップする。
    /// `nil` を返した場合は「キャンセル相当」を意味し、UI に何も表示しない (PRD §4.3.2)。
    static func map(_ error: Error) -> RepositorySearchError? {
        if isCancelled(error) { return nil }

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

        if error is URLError {
            return .network
        }

        return .network
    }

    /// `CancellationError` または `URLError(.cancelled)`（`HttpClientError.networkError` でラップされている場合も含む）を一括判定する。
    private static func isCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let httpError = error as? HttpClientError,
           case let .networkError(urlError) = httpError,
           urlError.code == .cancelled {
            return true
        }
        return false
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
