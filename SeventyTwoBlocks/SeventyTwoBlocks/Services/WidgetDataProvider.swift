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
    // Cached values from startLiveActivity - preserved during updateLiveActivity calls
    private var cachedAutoContinueEndAt: Date?
    private var cachedNextBlockIndex: Int?
    private var cachedNextBlockDisplayNumber: Int?
    private var cachedNextBlockTimerEndAt: Date?
    private var cachedNextBlockAutoContinueEndAt: Date?
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
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End ALL existing activities BEFORE starting new one
        // This prevents duplicate activities showing in Dynamic Island (race condition fix)
        let existingActivities = Activity<TimerActivityAttributes>.activities
        if !existingActivities.isEmpty {
            print("📱 Found \(existingActivities.count) existing Live Activities, ending them before starting new one...")
            let finalState = TimerActivityAttributes.ContentState(
                timerEndAt: Date(),
                timerStartedAt: Date(),
                category: nil,
                categoryColor: nil,
                label: nil,
                progress: 1.0,
                isBreak: false,
                isAutoContinue: false,
                autoContinueEndAt: nil,
                nextBlockIndex: nil,
                nextBlockDisplayNumber: nil,
                nextBlockTimerEndAt: nil,
                nextBlockAutoContinueEndAt: nil
            )
            // Use staleDate in the past to force immediate dismissal
            let content = ActivityContent(state: finalState, staleDate: Date().addingTimeInterval(-1))

            // End all activities sequentially (typically only 1-2 at most)
            for activity in existingActivities {
                await activity.end(content, dismissalPolicy: .immediate)
                print("📱 Ended activity: \(activity.id)")
            }
        }
        currentActivity = nil

        // Get dayStartHour for correct display number
        let dayStartHour = UserDefaults.standard.object(forKey: "dayStartHour") as? Int ?? 6

        let attributes = TimerActivityAttributes(
            blockIndex: blockIndex,
            blockDisplayNumber: BlockTimeUtils.displayBlockNumber(blockIndex, dayStartHour: dayStartHour),
            blockStartTime: BlockTimeUtils.blockToTime(blockIndex),
            blockEndTime: BlockTimeUtils.blockEndTime(blockIndex),
            isBreak: isBreak
        )

        // Pre-set autoContinueEndAt so the Live Activity can automatically transition
        // to showing the auto-continue countdown when the block timer expires,
        // even when the app is backgrounded. The widget checks (timerExpired && autoContinueEndAt != nil)
        // before showing auto-continue UI, so this won't cause premature display.
        let autoContinueSeconds: TimeInterval = isBreak ? 30 : 25
        let autoContinueEndAt = timerEndAt.addingTimeInterval(autoContinueSeconds)

        // Calculate next block info so Live Activity can continue after auto-continue
        let nextBlockIndex = blockIndex + 1
        let nextBlockTimerEndAt = nextBlockIndex < 72 ? BlockTimeUtils.blockEndDate(for: nextBlockIndex) : nil
        let nextBlockAutoContinueEndAt = nextBlockTimerEndAt?.addingTimeInterval(autoContinueSeconds)
        let nextBlockDisplayNum = nextBlockIndex < 72 ? BlockTimeUtils.displayBlockNumber(nextBlockIndex, dayStartHour: dayStartHour) : nil

        // Cache all values so updateLiveActivity can preserve them
        cachedAutoContinueEndAt = autoContinueEndAt
        cachedNextBlockIndex = nextBlockIndex < 72 ? nextBlockIndex : nil
        cachedNextBlockDisplayNumber = nextBlockDisplayNum
        cachedNextBlockTimerEndAt = nextBlockTimerEndAt
        cachedNextBlockAutoContinueEndAt = nextBlockAutoContinueEndAt

        let state = TimerActivityAttributes.ContentState(
            timerEndAt: timerEndAt,
            timerStartedAt: timerStartedAt,
            category: category,
            categoryColor: categoryColor,
            label: label,
            progress: progress,
            isBreak: isBreak,
            isAutoContinue: false,
            autoContinueEndAt: autoContinueEndAt,
            nextBlockIndex: cachedNextBlockIndex,
            nextBlockDisplayNumber: cachedNextBlockDisplayNumber,
            nextBlockTimerEndAt: nextBlockTimerEndAt,
            nextBlockAutoContinueEndAt: nextBlockAutoContinueEndAt
        )

        // Stale date extends to cover next block's auto-continue too
        let staleDate = nextBlockAutoContinueEndAt ?? timerEndAt.addingTimeInterval(120)
        let content = ActivityContent(state: state, staleDate: staleDate)

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

        // Preserve all cached values so TimelineView phase logic works correctly
        // Without these, the Live Activity loses the ability to transition through phases
        let state = TimerActivityAttributes.ContentState(
            timerEndAt: timerEndAt,
            timerStartedAt: timerStartedAt,
            category: category,
            categoryColor: categoryColor,
            label: label,
            progress: progress,
            isBreak: isBreak,
            isAutoContinue: false,
            autoContinueEndAt: cachedAutoContinueEndAt,
            nextBlockIndex: cachedNextBlockIndex,
            nextBlockDisplayNumber: cachedNextBlockDisplayNumber,
            nextBlockTimerEndAt: cachedNextBlockTimerEndAt,
            nextBlockAutoContinueEndAt: cachedNextBlockAutoContinueEndAt
        )

        // Stale date should extend to cover all phases
        let staleDate = cachedNextBlockAutoContinueEndAt ?? timerEndAt.addingTimeInterval(120)
        let content = ActivityContent(state: state, staleDate: staleDate)

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
            autoContinueEndAt: autoContinueEndAt,
            nextBlockIndex: nil,
            nextBlockDisplayNumber: nil,
            nextBlockTimerEndAt: nil,
            nextBlockAutoContinueEndAt: nil
        )

        let content = ActivityContent(state: state, staleDate: autoContinueEndAt.addingTimeInterval(60))

        Task {
            await activity.update(content)
        }
    }

    func endLiveActivity() {
        // End ALL running activities of this type, not just the one we have a reference to
        // This handles orphaned activities from app termination/restart or race conditions
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
                autoContinueEndAt: nil,
                nextBlockIndex: nil,
                nextBlockDisplayNumber: nil,
                nextBlockTimerEndAt: nil,
                nextBlockAutoContinueEndAt: nil
            )
            let content = ActivityContent(state: finalState, staleDate: nil)

            // End all activities of this type
            for activity in Activity<TimerActivityAttributes>.activities {
                await activity.end(content, dismissalPolicy: .immediate)
                print("📱 Live Activity ended: \(activity.id)")
            }
        }

        cachedAutoContinueEndAt = nil
        cachedNextBlockIndex = nil
        cachedNextBlockDisplayNumber = nil
        cachedNextBlockTimerEndAt = nil
        cachedNextBlockAutoContinueEndAt = nil
        currentActivity = nil
    }
    #else
    // Stub methods for Mac Catalyst where Live Activities aren't available
    func startLiveActivity(blockIndex: Int, isBreak: Bool, timerEndAt: Date, timerStartedAt: Date, category: String?, categoryColor: String?, label: String?, progress: Double) async {}
    func updateLiveActivity(timerEndAt: Date, timerStartedAt: Date, category: String?, categoryColor: String?, label: String?, progress: Double, isBreak: Bool) {}
    func updateLiveActivityForAutoContinue(autoContinueEndAt: Date, isBreak: Bool) {}
    func endLiveActivity() {}
    #endif
}
