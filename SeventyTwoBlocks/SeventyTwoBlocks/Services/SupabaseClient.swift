import Foundation
import Auth
import PostgREST
import Security

// MARK: - Supabase Configuration
enum SupabaseConfig {
    static let url = "https://kvosxgdogzziglbpjyts.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2b3N4Z2RvZ3p6aWdsYnBqeXRzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY2ODkxNTQsImV4cCI6MjA4MjI2NTE1NH0.v1mynv5W83raFacsJpraQfGzaRx_n89oHuYG5s4wYkA"

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
    let database: PostgrestClient

    private init() {
        // Initialize Auth client with configuration
        let authConfig = AuthClient.Configuration(
            url: SupabaseConfig.authURL,
            headers: ["apikey": SupabaseConfig.anonKey],
            localStorage: KeychainAuthStorage(),
            logger: nil
        )
        auth = AuthClient(configuration: authConfig)

        // Initialize PostgREST client
        database = PostgrestClient(
            url: SupabaseConfig.restURL,
            schema: "public",
            headers: [
                "apikey": SupabaseConfig.anonKey
            ],
            logger: nil
        )
    }
}

// Convenience accessors
var supabaseAuth: AuthClient {
    SupabaseManager.shared.auth
}

var supabaseDB: PostgrestClient {
    SupabaseManager.shared.database
}
