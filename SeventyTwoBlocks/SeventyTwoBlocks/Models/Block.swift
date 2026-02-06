import Foundation

// MARK: - Block Segment
// Note: Stored as JSONB in database with camelCase field names (from JavaScript)
// The database does NOT store an id field - we generate one locally for SwiftUI
struct BlockSegment: Codable, Identifiable {
    var id = UUID() // Local only, not in database
    let type: SegmentType
    var seconds: Int
    var category: String?
    var label: String?
    var startElapsed: Int?

    enum SegmentType: String, Codable {
        case work
        case `break`
    }

    // Only encode/decode the fields that exist in the database (not id)
    enum CodingKeys: String, CodingKey {
        case type, seconds, category, label, startElapsed
    }

    /// Composite id for SwiftUI ForEach that's deterministic based on content
    /// This ensures SwiftUI properly detects changes when segment seconds update
    var compositeId: String {
        "\(type.rawValue)-\(startElapsed ?? 0)-\(seconds)-\(category ?? "none")-\(label ?? "none")"
    }
}

// MARK: - Run
// Note: Stored as JSONB in database with camelCase field names (from JavaScript)
// Some fields may be missing from older records, so we use custom decoding with defaults
struct Run: Codable, Identifiable {
    let id: String
    let startedAt: Double
    var endedAt: Double?
    var initialRealTime: Double
    var scaleFactor: Double
    var segments: [BlockSegment]
    var currentSegmentStart: Double
    var currentType: BlockSegment.SegmentType
    var currentCategory: String?
    var lastWorkCategory: String?

    // No CodingKeys - use camelCase to match JavaScript/database

    // Custom decoder to handle missing fields with sensible defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        startedAt = try container.decode(Double.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Double.self, forKey: .endedAt)

        // These fields may be missing in older records - provide defaults
        initialRealTime = try container.decodeIfPresent(Double.self, forKey: .initialRealTime) ?? startedAt
        scaleFactor = try container.decodeIfPresent(Double.self, forKey: .scaleFactor) ?? 1.0
        segments = try container.decodeIfPresent([BlockSegment].self, forKey: .segments) ?? []
        currentSegmentStart = try container.decodeIfPresent(Double.self, forKey: .currentSegmentStart) ?? startedAt
        currentType = try container.decodeIfPresent(BlockSegment.SegmentType.self, forKey: .currentType) ?? .work
        currentCategory = try container.decodeIfPresent(String.self, forKey: .currentCategory)
        lastWorkCategory = try container.decodeIfPresent(String.self, forKey: .lastWorkCategory)
    }

    // Manual init for creating new runs
    init(id: String, startedAt: Double, endedAt: Double? = nil, initialRealTime: Double, scaleFactor: Double, segments: [BlockSegment], currentSegmentStart: Double, currentType: BlockSegment.SegmentType, currentCategory: String? = nil, lastWorkCategory: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.initialRealTime = initialRealTime
        self.scaleFactor = scaleFactor
        self.segments = segments
        self.currentSegmentStart = currentSegmentStart
        self.currentType = currentType
        self.currentCategory = currentCategory
        self.lastWorkCategory = lastWorkCategory
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, initialRealTime, scaleFactor, segments
        case currentSegmentStart, currentType, currentCategory, lastWorkCategory
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
    var visualFill: Double  // 0.0 to 1.0 - the actual visual fill reached during active timer
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
        case visualFill = "visual_fill"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Custom decoder to handle missing visualFill field (added in migration)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        date = try container.decode(String.self, forKey: .date)
        blockIndex = try container.decode(Int.self, forKey: .blockIndex)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isActivated = try container.decode(Bool.self, forKey: .isActivated)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        status = try container.decode(BlockStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        breakProgress = try container.decode(Double.self, forKey: .breakProgress)
        runs = try container.decodeIfPresent([Run].self, forKey: .runs)
        activeRunSnapshot = try container.decodeIfPresent(Run.self, forKey: .activeRunSnapshot)
        segments = try container.decodeIfPresent([BlockSegment].self, forKey: .segments) ?? []
        usedSeconds = try container.decodeIfPresent(Int.self, forKey: .usedSeconds) ?? 0
        // visualFill may be missing in older records - default to 0.0
        // For legacy done blocks with segments, we'll compute it from segments when needed
        visualFill = try container.decodeIfPresent(Double.self, forKey: .visualFill) ?? 0.0
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }

    // Memberwise initializer for creating blocks programmatically
    init(id: String, userId: String, date: String, blockIndex: Int, isMuted: Bool, isActivated: Bool, category: String?, label: String?, note: String?, status: BlockStatus, progress: Double, breakProgress: Double, runs: [Run]?, activeRunSnapshot: Run?, segments: [BlockSegment], usedSeconds: Int, visualFill: Double = 0.0, createdAt: String, updatedAt: String) {
        self.id = id
        self.userId = userId
        self.date = date
        self.blockIndex = blockIndex
        self.isMuted = isMuted
        self.isActivated = isActivated
        self.category = category
        self.label = label
        self.note = note
        self.status = status
        self.progress = progress
        self.breakProgress = breakProgress
        self.runs = runs
        self.activeRunSnapshot = activeRunSnapshot
        self.segments = segments
        self.usedSeconds = usedSeconds
        self.visualFill = visualFill
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom encode to ensure nil values are encoded as null (not omitted)
    // This is required for Supabase upsert to properly clear fields
    // Note: activeRunSnapshot and runs are excluded as they may not exist in the DB schema
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(date, forKey: .date)
        try container.encode(blockIndex, forKey: .blockIndex)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(isActivated, forKey: .isActivated)
        // Explicitly encode nil as null for optional fields
        try container.encode(category, forKey: .category)
        try container.encode(label, forKey: .label)
        try container.encode(note, forKey: .note)
        try container.encode(status, forKey: .status)
        // Database expects INTEGER for progress fields, not DOUBLE
        try container.encode(Int(progress), forKey: .progress)
        try container.encode(Int(breakProgress), forKey: .breakProgress)
        try container.encode(segments, forKey: .segments)
        try container.encode(usedSeconds, forKey: .usedSeconds)
        try container.encode(visualFill, forKey: .visualFill)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        // Don't encode runs and activeRunSnapshot - they may not exist in the DB
        // try container.encode(runs, forKey: .runs)
        // try container.encode(activeRunSnapshot, forKey: .activeRunSnapshot)
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

    /// Display block number in day-order (1-72)
    /// Morning (blockIndex 24-47) → display 1-24
    /// Afternoon (blockIndex 48-71) → display 25-48
    /// Night (blockIndex 0-23) → display 49-72
    static func displayBlockNumber(_ index: Int) -> Int {
        if index >= 24 {
            // Morning (24-47) → 1-24, Afternoon (48-71) → 25-48
            return index - 23
        } else {
            // Night (0-23) → 49-72
            return index + 49
        }
    }

    /// Get remaining seconds in a block based on current time
    /// Returns 0 if the block has already passed, or full 1200 if block hasn't started yet
    static func remainingSecondsInBlock(_ index: Int) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let hours = calendar.component(.hour, from: now)
        let minutes = calendar.component(.minute, from: now)
        let seconds = calendar.component(.second, from: now)

        let currentTotalSeconds = hours * 3600 + minutes * 60 + seconds
        let blockStartSeconds = index * 20 * 60  // Block starts at index * 20 minutes
        let blockEndSeconds = (index + 1) * 20 * 60  // Block ends at (index + 1) * 20 minutes

        if currentTotalSeconds >= blockEndSeconds {
            // Block has passed
            return 0
        } else if currentTotalSeconds < blockStartSeconds {
            // Block hasn't started yet - return full duration
            return 1200
        } else {
            // We're within the block - return remaining time
            return blockEndSeconds - currentTotalSeconds
        }
    }

    /// Get the end date/time for a specific block on a given date
    static func blockEndDate(for index: Int, on date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let blockEndMinutes = (index + 1) * 20
        return startOfDay.addingTimeInterval(TimeInterval(blockEndMinutes * 60))
    }
}
