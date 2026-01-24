import Foundation
import Supabase

// MARK: - Supabase Configuration
enum SupabaseConfig {
    // TODO: Replace with your actual Supabase credentials
    static let url = URL(string: "YOUR_SUPABASE_URL")!
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"
}

// MARK: - Supabase Client Singleton
final class SupabaseClientManager {
    static let shared = SupabaseClientManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
}

// Convenience accessor
var supabase: SupabaseClient {
    SupabaseClientManager.shared.client
}
