import Foundation
import SwiftUI

// MARK: - Category
struct Category: Codable, Identifiable {
    let id: String
    let userId: String
    var label: String
    var color: String // HSL format: "H S% L%"
    var labels: [String]
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case label, color, labels
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension Category {
    /// Convert HSL string to SwiftUI Color
    var swiftUIColor: Color {
        // Parse "H S% L%" format
        let components = color.split(separator: " ")
        guard components.count >= 3,
              let h = Double(components[0]),
              let sValue = Double(components[1].dropLast()),
              let lValue = Double(components[2].dropLast()) else {
            return .gray
        }
        let s = sValue / 100
        let l = lValue / 100
        return Color(hue: h / 360, saturation: s, brightness: l)
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
