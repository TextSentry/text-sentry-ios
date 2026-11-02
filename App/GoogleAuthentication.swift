import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum AccountError: Error, LocalizedError {
    case invalidConfiguration, invalidCallback, invalidTokens, signedOut, unavailable, subscriptionRequired

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Google sign-in is not configured correctly."
        case .invalidCallback: "Google sign-in could not be verified. Try again."
        case .invalidTokens, .signedOut: "Your session has expired. Sign in again."
        case .unavailable: "Unable to reach TextSentry. Try again."
        case .subscriptionRequired: "An active TextSentry subscription is required for managed AI access."
        }
    }
}

/// Use the existing Android Cognito public client and redirect URI: no client secret is distributed.
struct GoogleOAuthConfiguration {
    static let discovery = URL(string: "https://api.textsentry.org/v1/auth/config")!
    static let redirect = "textsentry://auth/callback"
    let clientID: String
    let issuer: URL

    static func parse(_ data: Data) throws -> Self {
        struct Wire: Decodable {
            let client_id: String
            let authorization_server: String
            let redirect_uri: String
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.redirect_uri == redirect,
              wire.client_id.range(of: "^[A-Za-z0-9]{3,128}$", options: .regularExpression) != nil,
              let url = URL(string: wire.authorization_server),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.port == nil, parts.user == nil,
              parts.password == nil, parts.path.isEmpty, parts.query == nil, parts.fragment == nil,
              let host = parts.host,
              host.range(of: #"^textsentry-prod-[0-9]{12}\.auth\.us-east-1\.amazoncognito\.com$"#,
                         options: .regularExpression) != nil
        else { throw AccountError.invalidConfiguration }
        return .init(clientID: wire.client_id, issuer: url)
    }

    func authorizationURL(state: String, challenge: String) -> URL {
        var url = URLComponents(url: issuer.appendingPathComponent("oauth2/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: Self.redirect),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "identity_provider", value: "Google"),
            .init(name: "prompt", value: "select_account")
        ]
        return url.url!
    }

    var tokenURL: URL { issuer.appendingPathComponent("oauth2/token") }

    static func authorizationCode(from callback: URL, state: String) throws -> String {
        guard callback.scheme == "textsentry", callback.host == "auth", callback.path == "/callback",
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.queryItems?.filter({ $0.name == "state" }).count == 1,
              components.queryItems?.first(where: { $0.name == "state" })?.value == state,
              components.queryItems?.filter({ $0.name == "code" }).count == 1,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.count <= 2048,
              components.queryItems?.first(where: { $0.name == "error" }) == nil
        else { throw AccountError.invalidCallback }
        return code
    }
}

enum OAuthPKCE {
    static func random() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "") +
                UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncoded()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct CognitoTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiry: Date

    static func parse(_ data: Data, previousRefreshToken: String? = nil, now: Date = Date()) throws -> Self {
        struct Wire: Decodable {
            let access_token: String
            let refresh_token: String?
            let token_type: String
            let expires_in: Double
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.token_type.lowercased() == "bearer",
              !wire.access_token.isEmpty, wire.access_token.count < 16_384,
              let refresh = wire.refresh_token ?? previousRefreshToken, !refresh.isEmpty,
              refresh.count < 16_384, wire.expires_in.isFinite,
              (60...86_400).contains(wire.expires_in)
        else { throw AccountError.invalidTokens }
        return .init(accessToken: wire.access_token, refreshToken: refresh,
                     expiry: now.addingTimeInterval(wire.expires_in))
    }
}

private final class RejectHTTPRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Ephemeral networking; rejects redirects so OAuth bearer credentials never follow a 30x.
enum AccountHTTP {
    static func send(_ request: URLRequest, maxBytes: Int = 8192) async throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: RejectHTTPRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, data.count <= maxBytes else {
                throw AccountError.unavailable
            }
            return (data, http.statusCode)
        } catch let error as AccountError {
            throw error
        } catch {
            throw AccountError.unavailable
        }
    }

    static func get(_ url: URL, bearer: String? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        return try await send(request)
    }

    static func exchange(configuration: GoogleOAuthConfiguration,
                         parameters: [URLQueryItem]) async throws -> Data {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        var body = URLComponents()
        body.queryItems = parameters
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        let (response, status) = try await send(request, maxBytes: 32_768)
        guard status == 200 else { throw AccountError.invalidTokens }
        return response
    }
}

@MainActor
final class GoogleAccountStore: ObservableObject {
    @Published private(set) var signedIn: Bool
    @Published private(set) var subscriptionLabel = "Subscription status not checked"
    private var session: ASWebAuthenticationSession?
    private var generation = 0
    private var cachedKey: String?
    private var cachedKeyExpiry: Date = .distantPast

    init() { signedIn = KeychainVault.read("cognito-session") != nil }

    private func storedTokens() throws -> CognitoTokens {
        guard let data = KeychainVault.read("cognito-session"),
              let tokens = try? JSONDecoder().decode(CognitoTokens.self, from: data) else {
            throw AccountError.signedOut
        }
        return tokens
    }

    func signIn() async throws {
        let currentGeneration = generation
        let (configurationData, status) = try await AccountHTTP.get(GoogleOAuthConfiguration.discovery)
        guard status == 200 else { throw AccountError.unavailable }
        let configuration = try GoogleOAuthConfiguration.parse(configurationData)
        let verifier = OAuthPKCE.random()
        let state = OAuthPKCE.random()
        let authURL = configuration.authorizationURL(state: state, challenge: OAuthPKCE.challenge(for: verifier))
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let browser = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "textsentry") { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? AccountError.invalidCallback) }
            }
            browser.prefersEphemeralWebBrowserSession = true
            browser.presentationContextProvider = self
            session = browser
            if !browser.start() {
                session = nil
                continuation.resume(throwing: AccountError.unavailable)
            }
        }
        session = nil
        guard currentGeneration == generation else { throw AccountError.signedOut }
        let code = try GoogleOAuthConfiguration.authorizationCode(from: callback, state: state)
        let data = try await AccountHTTP.exchange(configuration: configuration, parameters: [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "client_id", value: configuration.clientID),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: GoogleOAuthConfiguration.redirect),
            .init(name: "code_verifier", value: verifier)
        ])
        let tokens = try CognitoTokens.parse(data)
        guard currentGeneration == generation else { throw AccountError.signedOut }
        try KeychainVault.write(try JSONEncoder().encode(tokens), for: "cognito-session")
        signedIn = true
        subscriptionLabel = "Check account status in Settings"
    }

    func freshAccessToken() async throws -> String {
        let currentGeneration = generation
        let tokens = try storedTokens()
        if tokens.expiry > Date().addingTimeInterval(60) { return tokens.accessToken }
        let (configData, status) = try await AccountHTTP.get(GoogleOAuthConfiguration.discovery)
        guard status == 200 else { throw AccountError.unavailable }
        let configuration = try GoogleOAuthConfiguration.parse(configData)
        let data = try await AccountHTTP.exchange(configuration: configuration, parameters: [
            .init(name: "grant_type", value: "refresh_token"),
            .init(name: "client_id", value: configuration.clientID),
            .init(name: "refresh_token", value: tokens.refreshToken)
        ])
        let refreshed = try CognitoTokens.parse(data, previousRefreshToken: tokens.refreshToken)
        guard currentGeneration == generation,
              (try? storedTokens().refreshToken) == tokens.refreshToken else {
            throw AccountError.signedOut
        }
        try KeychainVault.write(try JSONEncoder().encode(refreshed), for: "cognito-session")
        return refreshed.accessToken
    }

    func checkAccount() async throws {
        let currentGeneration = generation
        let token = try await freshAccessToken()
        let (data, status) = try await AccountHTTP.get(URL(string: "https://api.textsentry.org/v1/me")!, bearer: token)
        guard currentGeneration == generation else { throw AccountError.signedOut }
        guard status == 200 else { throw AccountError.unavailable }
        subscriptionLabel = try ManagedAccountStatus.parse(data).label
    }

    /// Uses a subscribed user's existing managed key. Keys are never saved to disk or app groups.
    func managedKey() async throws -> String {
        let currentGeneration = generation
        if let cachedKey, cachedKeyExpiry > Date().addingTimeInterval(30) { return cachedKey }
        let accessToken = try await freshAccessToken()
        let (data, status) = try await AccountHTTP.get(URL(string: "https://api.textsentry.org/v1/key")!,
                                                        bearer: accessToken)
        guard currentGeneration == generation else { throw AccountError.signedOut }
        if status == 402 { throw AccountError.subscriptionRequired }
        guard status == 200 || status == 201 else { throw AccountError.unavailable }
        let key = try ManagedKeyResponse.parse(data)
        cachedKey = key.key
        cachedKeyExpiry = key.expiry
        return key.key
    }

    func signOut() {
        generation += 1
        session?.cancel()
        session = nil
        cachedKey = nil
        cachedKeyExpiry = .distantPast
        KeychainVault.delete("cognito-session")
        signedIn = false
        subscriptionLabel = "Subscription status not checked"
    }
}

extension GoogleAccountStore: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
