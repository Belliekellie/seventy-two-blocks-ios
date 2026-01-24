import Foundation

// MARK: - Block Segment
struct BlockSegment: Codable, Identifiable {
    var id = UUID()
    let type: SegmentType
    var seconds: Int
    var category: String?
    var label: String?
    var startElapsed: Int?

    enum SegmentType: String, Codable {
        case work
        case `break`
    }

    enum CodingKeys: String, CodingKey {
        case type, seconds, category, label
        case startElapsed = "start_elapsed"
    }
}

// MARK: - Run
struct Run: Codable, Identifiable {
    let id: String
    let startedAt: Double
    var endedAt: Double?
    let initialRealTime: Double
    let scaleFactor: Double
    var segments: [BlockSegment]
    var currentSegmentStart: Double
    var currentType: BlockSegment.SegmentType
    var currentCategory: String?
    var lastWorkCategory: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case initialRealTime = "initial_real_time"
        case scaleFactor = "scale_factor"
        case segments
        case currentSegmentStart = "current_segment_start"
        case currentType = "current_type"
        case currentCategory = "current_category"
        case lastWorkCategory = "last_work_category"
    }
}

// MARK: - Block Status
enum BlockStatus: String, Codable {
    case idle
    case planned
    case done
    case skipped
}

// MARK: - Block
struct Block: Codable, Identifiable {
    let id: String
    let userId: String
    let date: String
    let blockIndex: Int
    var isMuted: Bool
    var isActivated: Bool
    var category: String?
    var label: String?
    var note: String?
    var status: BlockStatus
    var progress: Double
    var breakProgress: Double
    var runs: [Run]?
    var activeRunSnapshot: Run?
    var segments: [BlockSegment]
    var usedSeconds: Int
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case blockIndex = "block_index"
        case isMuted = "is_muted"
        case isActivated = "is_activated"
        case category, label, note, status
        case progress
        case breakProgress = "break_progress"
        case runs
        case activeRunSnapshot = "active_run_snapshot"
        case segments
        case usedSeconds = "used_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Block Time Utilities
extension Block {
    /// Convert block index (0-71) to display time string
    static func blockToTime(_ index: Int) -> String {
        let totalMinutes = index * 20
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// Get end time for a block
    static func blockEndTime(_ index: Int) -> String {
        let totalMinutes = (index + 1) * 20
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// Get current block index based on time
    static func getCurrentBlockIndex() -> Int {
        let calendar = Calendar.current
        let now = Date()
        let hours = calendar.component(.hour, from: now)
        let minutes = calendar.component(.minute, from: now)
        let totalMinutes = hours * 60 + minutes
        return totalMinutes / 20
    }

    /// Display block number (1-72 for user display)
    static func displayBlockNumber(_ index: Int) -> Int {
        return index + 1
    }
}
