import Foundation

/// 既存 `HttpClient` を decorator として包み、認証ヘッダ注入とレート制限ヘッダの観測、
/// 401 発生時の `GitHubAuthState.handle401()` 発火を一元化する。
nonisolated struct AuthenticatedHttpClient: HttpClient {
    let upstream: HttpClient
    let authState: GitHubAuthState
    let rateLimit: RateLimitObserver

    func sendWithResponseMetadata<T: Decodable & Sendable>(_ request: HttpRequest) async throws -> HttpResponse<T> {
        let token = await authState.token
        let isGitHubAPI = Self.shouldAttachBearer(request: request)
        let augmented: HttpRequest
        if isGitHubAPI, let token {
            var headers = request.headers
            headers["Authorization"] = "Bearer \(token)"
            if headers["Accept"] == nil {
                headers["Accept"] = "application/vnd.github+json"
            }
            if headers["X-GitHub-Api-Version"] == nil {
                headers["X-GitHub-Api-Version"] = "2022-11-28"
            }
            augmented = HttpRequest(
                host: request.host,
                method: request.method,
                path: request.path,
                queryItems: request.queryItems,
                headers: headers
            )
        } else {
            augmented = request
        }

        do {
            let response: HttpResponse<T> = try await upstream.sendWithResponseMetadata(augmented)
            if isGitHubAPI {
                await rateLimit.update(from: response.headers)
            }
            return response
        } catch let HttpClientError.httpError(statusCode, data, headers) {
            if isGitHubAPI {
                await rateLimit.update(from: headers)
            }
            if statusCode == 401, isGitHubAPI {
                await authState.handle401()
            }
            throw HttpClientError.httpError(statusCode: statusCode, data: data, headers: headers)
        }
    }

    private static func shouldAttachBearer(request: HttpRequest) -> Bool {
        switch request.host {
        case .github:
            return true
        case let .custom(url):
            // テスト時に custom ホストを `api.github.com` 役として使う場合のフック。
            // GitHub OAuth 用ホスト (`github.com`) は production では Bearer 不要のため除外する。
            return url.host?.hasSuffix(".github.com") == true || url.host == "api.github.com"
        }
    }
}
