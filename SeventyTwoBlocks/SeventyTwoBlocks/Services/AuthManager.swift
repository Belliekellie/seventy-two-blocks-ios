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

    func checkSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await supabaseAuth.session
            currentUser = session.user
            isAuthenticated = true
        } catch {
            isAuthenticated = false
            currentUser = nil
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
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await supabaseAuth.signOut()
            isAuthenticated = false
            currentUser = nil
        } catch {
            self.error = error.localizedDescription
        }
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
        } catch {
            self.error = error.localizedDescription
        }
    }
}
