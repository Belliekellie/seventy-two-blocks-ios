import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

// MARK: - App Group Constants

enum WidgetConstants {
    static let appGroupID = "group.GKApps.SeventyTwoBlocks"
    static let widgetDataKey = "widgetData"
    static let blocksPerDay = 72
    static let blockDurationMinutes = 20
    static let blockDurationSeconds = 1200
}

// MARK: - Widget Block Status

enum WidgetBlockStatus: String, Codable {
    case idle
    case planned
    case done
    case skipped
    case muted
    case active // currently has a running timer
}

// MARK: - Widget Data (shared between app and widgets via App Group)

struct WidgetData: Codable {
    let currentBlockIndex: Int        // 0-71
    let blocksCompletedToday: Int
    let totalActiveBlocks: Int
    let timerActive: Bool
    let timerIsBreak: Bool
    let timerEndAt: Date?             // enables Text(date, style: .timer)
    let timerStartedAt: Date?         // enables ProgressView(timerInterval:)
    let timerBlockIndex: Int?
    let timerCategory: String?
    let timerCategoryColor: String?   // HSL format: "H S% L%"
    let timerLabel: String?
    let timerInitialTime: Int?
    let blockStatuses: [WidgetBlockEntry]
    let mainGoalText: String?
    let mainGoalComplete: Bool
    let hoursWorked: Double           // total work hours today
    let breaksTaken: Int              // number of break periods today
    let lastUpdated: Date

    static var empty: WidgetData {
        WidgetData(
            currentBlockIndex: BlockTimeUtils.getCurrentBlockIndex(),
            blocksCompletedToday: 0,
            totalActiveBlocks: 0,
            timerActive: false,
            timerIsBreak: false,
            timerEndAt: nil,
            timerStartedAt: nil,
            timerBlockIndex: nil,
            timerCategory: nil,
            timerCategoryColor: nil,
            timerLabel: nil,
            timerInitialTime: nil,
            blockStatuses: (0..<72).map { WidgetBlockEntry(index: $0, status: .idle, category: nil, categoryColor: nil, label: nil) },
            mainGoalText: nil,
            mainGoalComplete: false,
            hoursWorked: 0,
            breaksTaken: 0,
            lastUpdated: Date()
        )
    }
}

// MARK: - Widget Block Entry (lightweight per-block data for grid widget)

struct WidgetBlockEntry: Codable {
    let index: Int
    let status: WidgetBlockStatus
    let category: String?
    let categoryColor: String?  // HSL format
    let label: String?
}

// MARK: - Live Activity Attributes

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
struct TimerActivityAttributes: ActivityAttributes {
    // Static data (set when activity starts)
    let blockIndex: Int
    let blockDisplayNumber: Int
    let blockStartTime: String   // "08:00"
    let blockEndTime: String     // "08:20"
    let isBreak: Bool

    // Dynamic data (updated during activity)
    struct ContentState: Codable, Hashable {
        let timerEndAt: Date
        let timerStartedAt: Date      // for ProgressView(timerInterval:)
        let category: String?
        let categoryColor: String?    // HSL format
        let label: String?
        let progress: Double          // 0.0 - 1.0
        let isBreak: Bool
        let isAutoContinue: Bool      // true when showing auto-continue countdown
        let autoContinueEndAt: Date?  // when auto-continue will fire

        // Current block info (needed when reusing existing activity for new block)
        let currentBlockIndex: Int?
        let currentBlockDisplayNumber: Int?
        let currentBlockStartTime: String?  // "08:00"
        let currentBlockEndTime: String?    // "08:20"

        // Next block info (for continuous background display)
        let nextBlockIndex: Int?
        let nextBlockDisplayNumber: Int?
        let nextBlockTimerEndAt: Date?
        let nextBlockAutoContinueEndAt: Date?

        // Third block info (to match 3-block check-in limit)
        let thirdBlockIndex: Int?
        let thirdBlockDisplayNumber: Int?
        let thirdBlockTimerEndAt: Date?
        let thirdBlockAutoContinueEndAt: Date?
    }
}
#endif

// MARK: - Block Time Utilities (pure functions, no dependencies on Block model)

enum BlockTimeUtils {
    /// Convert block index (0-71) to display time string "h:mma" (e.g., "2:20pm")
    static func blockToTime(_ index: Int) -> String {
        let totalMinutes = index * WidgetConstants.blockDurationMinutes
        let hours24 = totalMinutes / 60
        let minutes = totalMinutes % 60
        let hours12 = hours24 == 0 ? 12 : (hours24 > 12 ? hours24 - 12 : hours24)
        let ampm = hours24 < 12 ? "am" : "pm"
        return String(format: "%d:%02d%@", hours12, minutes, ampm)
    }

    /// Get end time for a block "h:mma" (e.g., "2:40pm")
    static func blockEndTime(_ index: Int) -> String {
        let totalMinutes = (index + 1) * WidgetConstants.blockDurationMinutes
        let hours24 = totalMinutes / 60
        let minutes = totalMinutes % 60
        let hours12 = hours24 == 0 ? 12 : (hours24 > 12 ? hours24 - 12 : hours24)
        let ampm = hours24 < 12 ? "am" : "pm"
        return String(format: "%d:%02d%@", hours12, minutes, ampm)
    }

    /// Get current block index based on current time
    static func getCurrentBlockIndex() -> Int {
        let calendar = Calendar.current
        let now = Date()
        let hours = calendar.component(.hour, from: now)
        let minutes = calendar.component(.minute, from: now)
        let totalMinutes = hours * 60 + minutes
        return totalMinutes / WidgetConstants.blockDurationMinutes
    }

    /// Display block number in day-order (1-72) based on dayStartHour
    /// Block 1 is the first block of the user's day (at dayStartHour)
    /// Block 72 is the last block of the user's day (just before dayStartHour)
    static func displayBlockNumber(_ index: Int, dayStartHour: Int = 6) -> Int {
        // Convert dayStartHour to block index (3 blocks per hour)
        let dayStartBlock = dayStartHour * 3
        // Calculate how many blocks from the day start (wrapping around midnight)
        let blocksFromStart = (index - dayStartBlock + 72) % 72
        return blocksFromStart + 1
    }

    /// Get the end Date for a specific block index on a given date
    static func blockEndDate(for index: Int, on date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let blockEndMinutes = (index + 1) * WidgetConstants.blockDurationMinutes
        return startOfDay.addingTimeInterval(TimeInterval(blockEndMinutes * 60))
    }

    /// Get the start Date for a specific block index on a given date
    static func blockStartDate(for index: Int, on date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let blockStartMinutes = index * WidgetConstants.blockDurationMinutes
        return startOfDay.addingTimeInterval(TimeInterval(blockStartMinutes * 60))
    }

    /// Day progress as fraction (0.0 - 1.0) based on blocks completed out of total
    static func dayProgress(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}
