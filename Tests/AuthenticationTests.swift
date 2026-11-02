import XCTest
@testable import TextSentry

final class AuthenticationTests: XCTestCase {
    private let issuer = "https://textsentry-prod-641010880844.auth.us-east-1.amazoncognito.com"

    private func config(_ callback: String = GoogleOAuthConfiguration.redirect,
                        _ host: String? = nil) -> Data {
        let object = ["client_id": "PublicClient123",
                      "authorization_server": host ?? issuer,
                      "redirect_uri": callback]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testGoogleConfigurationPinsCognitoHostAndRedirect() throws {
        let settings = try GoogleOAuthConfiguration.parse(config())
        let url = settings.authorizationURL(state: "stateValue", challenge: "pkceChallenge")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        XCTAssertEqual(value("identity_provider"), "Google")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), "pkceChallenge")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("prompt"), "select_account")
        XCTAssertEqual(value("redirect_uri"), "textsentry://auth/callback")
    }

    func testConfigurationRejectsUntrustedEndpointsAndCallbacks() {
        for host in [
            "http://textsentry-prod-641010880844.auth.us-east-1.amazoncognito.com",
            "https://textsentry-prod-641010880844.auth.us-east-1.amazoncognito.com.evil.test",
            "https://evil.test",
            "https://textsentry-prod-641010880844.auth.us-east-1.amazoncognito.com/evil",
            "https://textsentry-prod-641010880844.auth.us-east-1.amazoncognito.com?redirect=evil",
            "https://textsentry-prod-641010880844.auth.us-east-1.amazoncognito.com:443"
        ] { XCTAssertThrowsError(try GoogleOAuthConfiguration.parse(config(GoogleOAuthConfiguration.redirect, host))) }
        XCTAssertThrowsError(try GoogleOAuthConfiguration.parse(config("evil://auth/callback")))
    }

    func testPKCEKnownVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(OAuthPKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(OAuthPKCE.random().count, 43)
    }

    func testOAuthCallbackRequiresExactStateAndCallback() throws {
        let callback = URL(string: "textsentry://auth/callback?code=validCode&state=expected")!
        XCTAssertEqual(try GoogleOAuthConfiguration.authorizationCode(from: callback, state: "expected"), "validCode")
        for raw in [
            "textsentry://auth/callback?code=a&state=wrong",
            "textsentry://auth/other?code=a&state=expected",
            "textsentry://other/callback?code=a&state=expected",
            "textsentry://auth/callback?code=a&state=expected&state=expected",
            "textsentry://auth/callback?code=a&state=expected&code=b",
            "textsentry://auth/callback?error=denied&state=expected"
        ] { XCTAssertThrowsError(try GoogleOAuthConfiguration.authorizationCode(from: URL(string: raw)!, state: "expected")) }
    }

    func testInitialTokensRequireRefreshTokenAndValidExpiry() throws {
        let valid = Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"token_type":"Bearer"}"#.utf8)
        let tokens = try CognitoTokens.parse(valid, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(tokens.refreshToken, "refresh")
        XCTAssertEqual(tokens.expiry.timeIntervalSince1970, 3600)
        XCTAssertThrowsError(try CognitoTokens.parse(Data(#"{"access_token":"a","expires_in":3600,"token_type":"Bearer"}"#.utf8)))
        let refreshed = Data(#"{"access_token":"new","expires_in":3600,"token_type":"Bearer"}"#.utf8)
        XCTAssertEqual(try CognitoTokens.parse(refreshed, previousRefreshToken: "refresh").refreshToken, "refresh")
        XCTAssertThrowsError(try CognitoTokens.parse(Data(#"{"access_token":"a","refresh_token":"b","expires_in":-1,"token_type":"Bearer"}"#.utf8)))
    }

    func testManagedKeyContractRejectsInsecureOrExpiredKeys() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let valid = Data(#"{"key":"sk-managed","period":"2026-11","expires_at":"2026-12-01T00:00:00Z","monthly_limit_usd":1.0}"#.utf8)
        XCTAssertEqual(try ManagedKeyResponse.parse(valid, now: now).key, "sk-managed")
        for raw in [
            #"{"key":"sk","period":"invalid","expires_at":"2026-12-01T00:00:00Z","monthly_limit_usd":1}"#,
            #"{"key":"sk","period":"2026-11","expires_at":"2026-12-01T00:00:00Z","monthly_limit_usd":9}"#,
            #"{"key":"sk","period":"2026-11","expires_at":"2001-01-01T00:00:00Z","monthly_limit_usd":1}"#,
            #"{"key":"","period":"2026-11","expires_at":"2026-12-01T00:00:00Z","monthly_limit_usd":1}"#
        ] { XCTAssertThrowsError(try ManagedKeyResponse.parse(Data(raw.utf8), now: now)) }
    }

    func testAccountStatusDoesNotMistakeSandboxForLiveEntitlement() throws {
        let sandbox = Data(#"{"user_id":"abc","subscription_status":"active","subscription_sandbox":true}"#.utf8)
        XCTAssertTrue(try ManagedAccountStatus.parse(sandbox).label.contains("Sandbox"))
        let live = Data(#"{"user_id":"abc","subscription_status":"active","subscription_sandbox":false}"#.utf8)
        XCTAssertEqual(try ManagedAccountStatus.parse(live).label, "Active subscription")
    }
}
