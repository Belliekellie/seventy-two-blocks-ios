import Foundation
import SwiftUI

// MARK: - Category Definition (stored in profiles.custom_categories JSON)
struct Category: Codable, Identifiable {
    let id: String
    var label: String
    var color: String // HSL format: "H S% L%"
    var labels: [String]? // Optional sub-labels for this category

    // Default categories matching web app
    static let defaults: [Category] = [
        Category(id: "work", label: "Work", color: "187 85% 53%", labels: nil),
        Category(id: "writing", label: "Writing", color: "280 70% 60%", labels: nil),
        Category(id: "admin", label: "Admin", color: "45 93% 58%", labels: nil),
        Category(id: "family", label: "Family", color: "340 82% 65%", labels: nil),
        Category(id: "training", label: "Training", color: "142 71% 45%", labels: nil),
        Category(id: "rest", label: "Rest", color: "215 25% 50%", labels: nil),
        Category(id: "commute", label: "Commute", color: "25 95% 60%", labels: nil),
        Category(id: "other", label: "Other", color: "260 50% 60%", labels: nil),
    ]
}

extension Category {
    /// Convert HSL string to SwiftUI Color
    var swiftUIColor: Color {
        // Parse "H S% L%" format (e.g., "187 85% 53%")
        let components = color.split(separator: " ")
        guard components.count >= 3 else {
            print("⚠️ Invalid color format: \(color)")
            return .gray
        }

        // Parse hue (no % sign)
        guard let h = Double(components[0]) else {
            print("⚠️ Invalid hue: \(components[0])")
            return .gray
        }

        // Parse saturation (remove % if present)
        let sString = String(components[1]).replacingOccurrences(of: "%", with: "")
        guard let sValue = Double(sString) else {
            print("⚠️ Invalid saturation: \(components[1])")
            return .gray
        }

        // Parse lightness (remove % if present)
        let lString = String(components[2]).replacingOccurrences(of: "%", with: "")
        guard let lValue = Double(lString) else {
            print("⚠️ Invalid lightness: \(components[2])")
            return .gray
        }

        let s = sValue / 100
        let l = lValue / 100

        // Convert HSL to HSB (SwiftUI uses HSB not HSL)
        // Formula: B = L + S * min(L, 1-L)
        //          S_hsb = B == 0 ? 0 : 2 * (1 - L/B)
        let b = l + s * min(l, 1 - l)
        let sHsb = b == 0 ? 0 : 2 * (1 - l / b)

        return Color(hue: h / 360, saturation: sHsb, brightness: b)
    }
}

// MARK: - Profile
struct Profile: Codable, Identifiable {
    let id: String
    let userId: String
    var email: String?
    var streakThreshold: Int
    var dayStartHour: Int
    var autoActivateSleepBlocks: Bool
    var disableAutoContinue: Bool
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case email
        case streakThreshold = "streak_threshold"
        case dayStartHour = "day_start_hour"
        case autoActivateSleepBlocks = "auto_activate_sleep_blocks"
        case disableAutoContinue = "disable_auto_continue"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Day Settings
struct DaySettings: Codable, Identifiable {
    let id: String
    let userId: String
    let date: String
    var sleepStartBlock: Int
    var sleepEndBlock: Int
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case sleepStartBlock = "sleep_start_block"
        case sleepEndBlock = "sleep_end_block"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
