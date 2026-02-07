import Foundation
import WidgetKit
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

@MainActor
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()

    private let userDefaults = UserDefaults(suiteName: WidgetConstants.appGroupID)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private var currentActivity: Activity<TimerActivityAttributes>?
    #endif

    private init() {
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    // MARK: - Write Widget Data

    func updateWidgetData(
        blocks: [Block],
        categories: [Category],
        timerManager: TimerManager,
        goalManager: GoalManager? = nil
    ) {
        let currentBlockIndex = Block.getCurrentBlockIndex()

        let completedBlocks = blocks.filter { $0.status == .done && !$0.isMuted }.count
        let activeBlocks = blocks.filter { !$0.isMuted }.count

        // Find category color for timer
        let timerCategoryColor: String? = {
            guard let catName = timerManager.currentCategory else { return nil }
            return categories.first { $0.id == catName }?.color
        }()

        // Calculate hours worked from segments (or assume full block for blocks without segments)
        let workSeconds = blocks.filter { $0.status == .done && !$0.isMuted }.reduce(0) { total, block in
            let workSegSeconds = block.segments.filter { $0.type == .work }.reduce(0) { $0 + $1.seconds }
            return total + (workSegSeconds > 0 ? workSegSeconds : 1200)
        }
        let hoursWorked = Double(workSeconds) / 3600.0

        // Count break periods across all blocks
        let breaksTaken = blocks.reduce(0) { total, block in
            total + block.segments.filter { $0.type == .break }.count
        }

        // Build block status entries
        let blockEntries: [WidgetBlockEntry] = blocks.map { block in
            let status: WidgetBlockStatus
            if timerManager.isActive && timerManager.currentBlockIndex == block.blockIndex {
                status = .active
            } else if block.isMuted {
                status = .muted
            } else {
                switch block.status {
                case .idle: status = .idle
                case .planned: status = .planned
                case .done: status = .done
                case .skipped: status = .skipped
                }
            }

            let matchedCat = categories.first { $0.id == block.category }
            return WidgetBlockEntry(
                index: block.blockIndex,
                status: status,
                category: matchedCat?.label ?? block.category,
                categoryColor: matchedCat?.color,
                label: block.label
            )
        }

        let widgetData = WidgetData(
            currentBlockIndex: currentBlockIndex,
            blocksCompletedToday: completedBlocks,
            totalActiveBlocks: activeBlocks,
            timerActive: timerManager.isActive,
            timerIsBreak: timerManager.isBreak,
            timerEndAt: timerManager.exposedEndAt,
            timerStartedAt: timerManager.exposedStartedAt,
            timerBlockIndex: timerManager.currentBlockIndex,
            timerCategory: categories.first { $0.id == timerManager.currentCategory }?.label ?? timerManager.currentCategory,
            timerCategoryColor: timerCategoryColor,
            timerLabel: timerManager.currentLabel,
            timerInitialTime: timerManager.isActive ? timerManager.initialTime : nil,
            blockStatuses: blockEntries,
            mainGoalText: goalManager?.mainGoal?.text,
            mainGoalComplete: goalManager?.mainGoal?.isComplete ?? false,
            hoursWorked: hoursWorked,
            breaksTaken: breaksTaken,
            lastUpdated: Date()
        )

        // Write to App Group UserDefaults
        if let data = try? encoder.encode(widgetData) {
            userDefaults?.set(data, forKey: WidgetConstants.widgetDataKey)
        }

        // Sync dayStartHour so widgets can detect stale data across day boundaries
        let dayStartHour = UserDefaults.standard.object(forKey: "dayStartHour") as? Int ?? 6
        userDefaults?.set(dayStartHour, forKey: "dayStartHour")

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Live Activity Management

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    func startLiveActivity(
        blockIndex: Int,
        isBreak: Bool,
        timerEndAt: Date,
        timerStartedAt: Date,
        category: String?,
        categoryColor: String?,
        label: String?,
        progress: Double
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing activity first
        endLiveActivity()

        let attributes = TimerActivityAttributes(
            blockIndex: blockIndex,
            blockDisplayNumber: BlockTimeUtils.displayBlockNumber(blockIndex),
            blockStartTime: BlockTimeUtils.blockToTime(blockIndex),
            blockEndTime: BlockTimeUtils.blockEndTime(blockIndex),
            isBreak: isBreak
        )

        let state = TimerActivityAttributes.ContentState(
            timerEndAt: timerEndAt,
            timerStartedAt: timerStartedAt,
            category: category,
            categoryColor: categoryColor,
            label: label,
            progress: progress,
            isBreak: isBreak,
            isAutoContinue: false,
            autoContinueEndAt: nil
        )

        let content = ActivityContent(state: state, staleDate: timerEndAt.addingTimeInterval(60))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            print("📱 Live Activity started for block \(blockIndex)")
        } catch {
            print("📱 Failed to start Live Activity: \(error)")
        }
    }

    func updateLiveActivity(
        timerEndAt: Date,
        timerStartedAt: Date,
        category: String?,
        categoryColor: String?,
        label: String?,
        progress: Double,
        isBreak: Bool
    ) {
        guard let activity = currentActivity else { return }

        let state = TimerActivityAttributes.ContentState(
            timerEndAt: timerEndAt,
            timerStartedAt: timerStartedAt,
            category: category,
            categoryColor: categoryColor,
            label: label,
            progress: progress,
            isBreak: isBreak,
            isAutoContinue: false,
            autoContinueEndAt: nil
        )

        let content = ActivityContent(state: state, staleDate: timerEndAt.addingTimeInterval(60))

        Task {
            await activity.update(content)
        }
    }

    func updateLiveActivityForAutoContinue(
        autoContinueEndAt: Date,
        isBreak: Bool
    ) {
        guard let activity = currentActivity else { return }

        let state = TimerActivityAttributes.ContentState(
            timerEndAt: autoContinueEndAt,
            timerStartedAt: Date(),
            category: nil,
            categoryColor: nil,
            label: isBreak ? "Break done" : "Block done",
            progress: 1.0,
            isBreak: isBreak,
            isAutoContinue: true,
            autoContinueEndAt: autoContinueEndAt
        )

        let content = ActivityContent(state: state, staleDate: autoContinueEndAt.addingTimeInterval(60))

        Task {
            await activity.update(content)
        }
    }

    func endLiveActivity() {
        guard let activity = currentActivity else { return }

        Task {
            let finalState = TimerActivityAttributes.ContentState(
                timerEndAt: Date(),
                timerStartedAt: Date(),
                category: nil,
                categoryColor: nil,
                label: nil,
                progress: 1.0,
                isBreak: false,
                isAutoContinue: false,
                autoContinueEndAt: nil
            )
            let content = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(content, dismissalPolicy: .immediate)
            print("📱 Live Activity ended")
        }

        currentActivity = nil
    }
    #else
    // Stub methods for Mac Catalyst where Live Activities aren't available
    func startLiveActivity(blockIndex: Int, isBreak: Bool, timerEndAt: Date, timerStartedAt: Date, category: String?, categoryColor: String?, label: String?, progress: Double) {}
    func updateLiveActivity(timerEndAt: Date, timerStartedAt: Date, category: String?, categoryColor: String?, label: String?, progress: Double, isBreak: Bool) {}
    func updateLiveActivityForAutoContinue(autoContinueEndAt: Date, isBreak: Bool) {}
    func endLiveActivity() {}
    #endif
}
