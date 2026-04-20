import Foundation
import AuthenticationServices

@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    private(set) var isSignedIn = false
    private(set) var userId: String?
    private(set) var userEmail: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let keychainService = "com.equiedge.app"
    private let keychainUserIdKey = "appleUserId"
    private let keychainEmailKey = "appleUserEmail"
    private let vercelBaseURL = "https://equiedge-scraper.vercel.app"

    private init() {
        // Restore session from Keychain on init
        if let storedId = keychainRead(key: keychainUserIdKey) {
            userId = storedId
            userEmail = keychainRead(key: keychainEmailKey)
            isSignedIn = true
        }
    }

    // MARK: - Sign In with Apple

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Unexpected credential type"
                return
            }
            await processAppleCredential(credential)

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
    }

    private func processAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            errorMessage = "Missing identity token"
            return
        }

        let userIdentifier = credential.user
        let email = credential.email // Only provided on first sign-in

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authenticateWithBackend(
                identityToken: identityToken,
                userIdentifier: userIdentifier
            )

            // Store in Keychain (survives app deletion)
            keychainWrite(key: keychainUserIdKey, value: response.userId)
            if let email = email ?? response.email {
                keychainWrite(key: keychainEmailKey, value: email)
                userEmail = email
            }

            userId = response.userId
            isSignedIn = true
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Authentication failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sign Out

    func signOut() {
        keychainDelete(key: keychainUserIdKey)
        keychainDelete(key: keychainEmailKey)
        userId = nil
        userEmail = nil
        isSignedIn = false
    }

    // MARK: - Backend Auth

    private struct AuthResponse: Codable {
        let userId: String
        let isNewUser: Bool
        let email: String?
        let tier: String
    }

    private func authenticateWithBackend(identityToken: String, userIdentifier: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(vercelBaseURL)/api/auth/apple") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "identityToken": identityToken,
            "userIdentifier": userIdentifier
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "AuthManager", code: statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Server returned \(statusCode): \(body)"
            ])
        }

        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    // MARK: - Keychain Helpers

    private func keychainWrite(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func keychainRead(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
