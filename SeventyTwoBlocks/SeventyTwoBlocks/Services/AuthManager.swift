import Foundation
import Combine
import Auth
import AuthenticationServices

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: Auth.User?
    @Published var isLoading = false
    @Published var error: String?

    private let hasLoggedInKey = "authManager_hasLoggedInBefore"

    /// Whether the user has ever successfully logged in on this device.
    /// Once true, we let them into the app even without internet.
    private var hasLoggedInBefore: Bool {
        get { UserDefaults.standard.bool(forKey: hasLoggedInKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasLoggedInKey) }
    }

    func checkSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await supabaseAuth.session
            currentUser = session.user
            isAuthenticated = true
            hasLoggedInBefore = true
        } catch {
            // Session check failed (no internet, token expired, etc.)
            // If the user has logged in before, let them in anyway —
            // the app works offline with local data.
            if hasLoggedInBefore {
                isAuthenticated = true
                currentUser = nil
                print("⚠️ Session check failed but user has logged in before — allowing offline access")
            } else {
                isAuthenticated = false
                currentUser = nil
            }
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let session = try await supabaseAuth.signIn(
                email: email,
                password: password
            )
            currentUser = session.user
            isAuthenticated = true
            hasLoggedInBefore = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let response = try await supabaseAuth.signUp(
                email: email,
                password: password
            )
            if let session = response.session {
                currentUser = session.user
                isAuthenticated = true
                hasLoggedInBefore = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await supabaseAuth.signOut()
        } catch {
            self.error = error.localizedDescription
        }
        // Always clear auth state on sign out, even if the network call fails
        isAuthenticated = false
        currentUser = nil
        hasLoggedInBefore = false
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            error = "Failed to get Apple ID token"
            return
        }

        do {
            let session = try await supabaseAuth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString
                )
            )
            currentUser = session.user
            isAuthenticated = true
            hasLoggedInBefore = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
