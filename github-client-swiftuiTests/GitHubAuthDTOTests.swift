import Foundation
import Testing
@testable import github_client_swiftui

struct GitHubDeviceCodeDTOTests {

    @Test func decode_typicalResponse_mapsToDomain() throws {
        let json = """
        {
            "device_code": "3584d83530557fdd1f46af8289938c8ef79f9dc5",
            "user_code": "WDJB-MJHT",
            "verification_uri": "https://github.com/login/device",
            "expires_in": 900,
            "interval": 5
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(GitHubDeviceCodeDTO.self, from: json)
        let domain = dto.toDomain()

        #expect(domain.deviceCode == "3584d83530557fdd1f46af8289938c8ef79f9dc5")
        #expect(domain.userCode == "WDJB-MJHT")
        #expect(domain.verificationURL == URL(string: "https://github.com/login/device"))
        #expect(domain.expiresIn == 900)
        #expect(domain.interval == 5)
    }
}

struct GitHubAuthTokenResponseDTOTests {

    @Test func decode_success_returnsAccessToken() throws {
        let json = """
        {
            "access_token": "gho_xxx",
            "token_type": "bearer",
            "scope": "read:user"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(GitHubAuthTokenResponseDTO.self, from: json)
        switch dto.outcome {
        case let .success(token):
            #expect(token == "gho_xxx")
        case .pending, .slowDown, .accessDenied, .expiredToken, .otherError:
            Issue.record("Expected success outcome, got \(dto.outcome)")
        }
    }

    @Test func decode_authorizationPending_returnsPending() throws {
        let json = #"{"error":"authorization_pending","error_description":"The user has not yet authorized."}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(GitHubAuthTokenResponseDTO.self, from: json)
        if case .pending = dto.outcome { } else {
            Issue.record("Expected .pending outcome, got \(dto.outcome)")
        }
    }

    @Test func decode_slowDown_returnsSlowDown() throws {
        let json = #"{"error":"slow_down","error_description":"Too many requests."}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(GitHubAuthTokenResponseDTO.self, from: json)
        if case .slowDown = dto.outcome { } else {
            Issue.record("Expected .slowDown outcome, got \(dto.outcome)")
        }
    }

    @Test func decode_accessDenied_returnsAccessDenied() throws {
        let json = #"{"error":"access_denied","error_description":"The user denied."}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(GitHubAuthTokenResponseDTO.self, from: json)
        if case .accessDenied = dto.outcome { } else {
            Issue.record("Expected .accessDenied outcome, got \(dto.outcome)")
        }
    }

    @Test func decode_expiredToken_returnsExpired() throws {
        let json = #"{"error":"expired_token","error_description":"The token has expired."}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(GitHubAuthTokenResponseDTO.self, from: json)
        if case .expiredToken = dto.outcome { } else {
            Issue.record("Expected .expiredToken outcome, got \(dto.outcome)")
        }
    }

    @Test func decode_unknownError_returnsOtherError() throws {
        let json = #"{"error":"unsupported_grant_type","error_description":"unknown"}"#.data(using: .utf8)!
        let dto = try JSONDecoder().decode(GitHubAuthTokenResponseDTO.self, from: json)
        if case let .otherError(code) = dto.outcome {
            #expect(code == "unsupported_grant_type")
        } else {
            Issue.record("Expected .otherError outcome, got \(dto.outcome)")
        }
    }
}

struct GitHubAuthenticatedUserDTOTests {

    @Test func decode_withName_mapsName() throws {
        let json = """
        {
            "login": "octocat",
            "id": 1,
            "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
            "name": "The Octocat"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(GitHubAuthenticatedUserDTO.self, from: json)
        let domain = dto.toDomain()

        #expect(domain.login == "octocat")
        #expect(domain.name == "The Octocat")
        #expect(domain.avatarURL == URL(string: "https://avatars.githubusercontent.com/u/1?v=4"))
    }

    @Test func decode_nullName_mapsToNil() throws {
        let json = """
        {
            "login": "octocat",
            "id": 1,
            "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
            "name": null
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(GitHubAuthenticatedUserDTO.self, from: json)
        #expect(dto.toDomain().name == nil)
    }
}
