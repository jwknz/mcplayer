import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

enum AuthError: Error {
    case notSignedIn
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

@MainActor
final class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthManager()

    @Published private(set) var isSignedIn: Bool
    @Published var lastError: String?

    private var accessToken: String?
    private var accessTokenExpiresAt: Date?
    private let refreshTokenKey = "refreshToken"
    private var session: ASWebAuthenticationSession?

    private let scope = "https://www.googleapis.com/auth/youtube.readonly"
    private let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"

    private override init() {
        isSignedIn = KeychainStore.load(key: "refreshToken") != nil
        super.init()
    }

    func signIn() {
        let verifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: authEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Config.clientID),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        let authSession = ASWebAuthenticationSession(
            url: components.url!,
            callbackURLScheme: Config.redirectScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.handleCallback(callbackURL: callbackURL, error: error, verifier: verifier)
            }
        }
        authSession.presentationContextProvider = self
        authSession.prefersEphemeralWebBrowserSession = false
        session = authSession
        authSession.start()
    }

    private func handleCallback(callbackURL: URL?, error: Error?, verifier: String) async {
        if let error {
            lastError = "Sign-in failed: \(error.localizedDescription)"
            return
        }
        guard let callbackURL,
              let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
            lastError = "Sign-in failed: no authorization code returned."
            return
        }
        await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async {
        let body = [
            "code": code,
            "client_id": Config.clientID,
            "redirect_uri": Config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        do {
            let token = try await postToken(body: body)
            applyToken(token)
        } catch {
            lastError = "Sign-in failed: couldn't exchange authorization code (\(error.localizedDescription))."
        }
    }

    private func postToken(body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func applyToken(_ token: TokenResponse) {
        accessToken = token.accessToken
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        if let refreshToken = token.refreshToken {
            KeychainStore.save(refreshToken, key: refreshTokenKey)
        }
        isSignedIn = true
        lastError = nil
    }

    func signOut() {
        KeychainStore.delete(key: refreshTokenKey)
        accessToken = nil
        accessTokenExpiresAt = nil
        isSignedIn = false
    }

    /// Returns a valid access token, silently refreshing via the stored
    /// refresh token if the cached one is missing or close to expiry. This
    /// is what lets the iOS app stay signed in indefinitely without a
    /// backend — the refresh token was issued to a PKCE "iOS" client, which
    /// unlike the web app's implicit-flow client doesn't need a client
    /// secret to redeem it.
    func validAccessToken() async throws -> String {
        if let accessToken, let expiresAt = accessTokenExpiresAt, expiresAt > Date().addingTimeInterval(30) {
            return accessToken
        }
        guard let refreshToken = KeychainStore.load(key: refreshTokenKey) else {
            throw AuthError.notSignedIn
        }
        let body = [
            "client_id": Config.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        do {
            let token = try await postToken(body: body)
            accessToken = token.accessToken
            accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
            return token.accessToken
        } catch {
            signOut()
            throw AuthError.notSignedIn
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(hashed))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
