import Foundation

// MARK: - Main Goal (OneThing)
struct MainGoal: Codable, Identifiable {
    let id: String
    let userId: String
    let date: String
    var text: String
    var isComplete: Bool
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case text
        case isComplete = "is_complete"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func empty(for date: String) -> MainGoal {
        MainGoal(
            id: UUID().uuidString,
            userId: "",
            date: date,
            text: "",
            isComplete: false,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

// MARK: - Supporting Action
struct SupportingAction: Codable, Identifiable {
    let id: String
    let userId: String
    let date: String
    var text: String
    var isComplete: Bool
    var sortOrder: Int
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case text
        case isComplete = "is_complete"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
