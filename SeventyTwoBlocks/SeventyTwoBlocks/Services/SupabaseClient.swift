import Foundation
import Auth
import PostgREST
import Security

// MARK: - Supabase Configuration (72 Blocks - btsveepnfeynrctpmlyi)
enum SupabaseConfig {
    static let url = "https://btsveepnfeynrctpmlyi.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0c3ZlZXBuZmV5bnJjdHBtbHlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc5NDc3NjksImV4cCI6MjA4MzUyMzc2OX0.sDBxjP_YyoxqzS1sVCZoq4COIO9KGM2HyST4wqqD2RU"

    static var baseURL: URL {
        URL(string: url)!
    }

    static var restURL: URL {
        URL(string: "\(url)/rest/v1")!
    }

    static var authURL: URL {
        URL(string: "\(url)/auth/v1")!
    }
}

// MARK: - Auth Local Storage using Keychain
final class KeychainAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let service = "com.seventytwoblocks.auth"
    private let lock = NSLock()

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = value
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Supabase Clients
final class SupabaseManager: @unchecked Sendable {
    static let shared = SupabaseManager()

    let auth: AuthClient
    private let storage = KeychainAuthStorage()

    /// Get database client with current auth token
    func getDatabase() async -> PostgrestClient {
        var headers: [String: String] = ["apikey": SupabaseConfig.anonKey]

        // Try to get current access token from session
        do {
            let session = try await auth.session
            headers["Authorization"] = "Bearer \(session.accessToken)"
            print("✅ Got auth token for user: \(session.user.id)")
        } catch {
            print("⚠️ No active session for database request: \(error)")
        }

        return PostgrestClient(
            url: SupabaseConfig.restURL,
            schema: "public",
            headers: headers,
            logger: nil
        )
    }

    /// Synchronous database client (for compatibility, may not have auth token)
    var database: PostgrestClient {
        PostgrestClient(
            url: SupabaseConfig.restURL,
            schema: "public",
            headers: ["apikey": SupabaseConfig.anonKey],
            logger: nil
        )
    }

    private init() {
        // Initialize Auth client with configuration
        let authConfig = AuthClient.Configuration(
            url: SupabaseConfig.authURL,
            headers: ["apikey": SupabaseConfig.anonKey],
            localStorage: KeychainAuthStorage(),
            logger: nil
        )
        auth = AuthClient(configuration: authConfig)
    }
}

// Convenience accessors
var supabaseAuth: AuthClient {
    SupabaseManager.shared.auth
}

var supabaseDB: PostgrestClient {
    SupabaseManager.shared.database
}

func supabaseDBAsync() async -> PostgrestClient {
    await SupabaseManager.shared.getDatabase()
}
