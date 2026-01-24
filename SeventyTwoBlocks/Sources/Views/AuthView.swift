import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Logo/Title
                VStack(spacing: 8) {
                    Text("72")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Blocks")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)

                Spacer()

                // Auth form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isSignUp ? .newPassword : .password)

                    if let error = authManager.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task {
                            if isSignUp {
                                await authManager.signUp(email: email, password: password)
                            } else {
                                await authManager.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        if authManager.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isSignUp ? "Sign Up" : "Sign In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)

                    Button {
                        isSignUp.toggle()
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 32)

                // Divider
                HStack {
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 32)

                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                            Task {
                                await authManager.signInWithApple(credential: credential)
                            }
                        }
                    case .failure(let error):
                        authManager.error = error.localizedDescription
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthManager())
}
