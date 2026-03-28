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
    // Current block cache (needed when reusing existing activity)
    private var cachedCurrentBlockIndex: Int?
    private var cachedCurrentBlockDisplayNumber: Int?
    private var cachedCurrentBlockStartTime: String?
    private var cachedCurrentBlockEndTime: String?
    // Upcoming blocks cache (variable count based on check-in setting)
    private var cachedUpcomingBlocks: [UpcomingBlockInfo] = []
    private var cachedSessionEndAt: Date = Date()
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

        // Check if user has disabled Live Activities in app settings
        // Default is true (enabled) — UserDefaults.bool returns false for unset keys,
        // so we check if the key exists first.
        if UserDefaults.standard.object(forKey: "liveActivityEnabled") != nil {
            guard UserDefaults.standard.bool(forKey: "liveActivityEnabled") else { return }
        }

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
                currentBlockIndex: nil,
                currentBlockDisplayNumber: nil,
                currentBlockStartTime: nil,
                currentBlockEndTime: nil,
                upcomingBlocks: [],
                sessionEndAt: Date()
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

        // Read check-in limit from settings (same UserDefaults that @AppStorage uses)
        let blocksUntilCheckIn = UserDefaults.standard.object(forKey: "blocksUntilCheckIn") as? Int ?? 3

        // Partial blocks don't count toward the check-in limit
        let isPartial = timerEndAt.timeIntervalSince(timerStartedAt) < 1140
        let upcomingCount = blocksUntilCheckIn + (isPartial ? 1 : 0)

        // Build the upcoming blocks array
        var upcoming: [UpcomingBlockInfo] = []
        var prevEnd = autoContinueEndAt  // first upcoming block starts when current's auto-continue ends

        for i in 1...upcomingCount {
            let upIndex = blockIndex + i
            guard upIndex < 72 else { break }

            let isLast = (i == upcomingCount)
            let upEndAt = BlockTimeUtils.blockEndDate(for: upIndex)
            let upAcEnd = isLast ? nil : upEndAt.addingTimeInterval(autoContinueSeconds)

            upcoming.append(UpcomingBlockInfo(
                displayNumber: BlockTimeUtils.displayBlockNumber(upIndex, dayStartHour: dayStartHour),
                timerStartAt: prevEnd,
                timerEndAt: upEndAt,
                autoContinueEndAt: upAcEnd
            ))

            prevEnd = upAcEnd ?? upEndAt
        }

        let sessionEndAt = upcoming.last?.timerEndAt ?? timerEndAt

        // Cache all values so updateLiveActivity can preserve them
        cachedAutoContinueEndAt = autoContinueEndAt
        cachedCurrentBlockIndex = blockIndex
        cachedCurrentBlockDisplayNumber = BlockTimeUtils.displayBlockNumber(blockIndex, dayStartHour: dayStartHour)
        cachedCurrentBlockStartTime = BlockTimeUtils.blockToTime(blockIndex)
        cachedCurrentBlockEndTime = BlockTimeUtils.blockEndTime(blockIndex)
        cachedUpcomingBlocks = upcoming
        cachedSessionEndAt = sessionEndAt

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
            currentBlockIndex: blockIndex,
            currentBlockDisplayNumber: BlockTimeUtils.displayBlockNumber(blockIndex, dayStartHour: dayStartHour),
            currentBlockStartTime: BlockTimeUtils.blockToTime(blockIndex),
            currentBlockEndTime: BlockTimeUtils.blockEndTime(blockIndex),
            upcomingBlocks: upcoming,
            sessionEndAt: sessionEndAt
        )

        // Stale date extends to cover the full session
        let staleDate = cachedSessionEndAt.addingTimeInterval(60)
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
            currentBlockIndex: cachedCurrentBlockIndex,
            currentBlockDisplayNumber: cachedCurrentBlockDisplayNumber,
            currentBlockStartTime: cachedCurrentBlockStartTime,
            currentBlockEndTime: cachedCurrentBlockEndTime,
            upcomingBlocks: cachedUpcomingBlocks,
            sessionEndAt: cachedSessionEndAt
        )

        // Stale date should extend to cover the full session
        let staleDate = cachedSessionEndAt.addingTimeInterval(60)
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
            currentBlockIndex: cachedCurrentBlockIndex,
            currentBlockDisplayNumber: cachedCurrentBlockDisplayNumber,
            currentBlockStartTime: cachedCurrentBlockStartTime,
            currentBlockEndTime: cachedCurrentBlockEndTime,
            upcomingBlocks: cachedUpcomingBlocks,
            sessionEndAt: cachedSessionEndAt
        )

        // Stale date should cover the full session
        let staleDate = cachedSessionEndAt.addingTimeInterval(60)
        let content = ActivityContent(state: state, staleDate: staleDate)

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
                currentBlockIndex: nil,
                currentBlockDisplayNumber: nil,
                currentBlockStartTime: nil,
                currentBlockEndTime: nil,
                upcomingBlocks: [],
                sessionEndAt: Date()
            )
            let content = ActivityContent(state: finalState, staleDate: nil)

            // End all activities of this type
            for activity in Activity<TimerActivityAttributes>.activities {
                await activity.end(content, dismissalPolicy: .immediate)
                print("📱 Live Activity ended: \(activity.id)")
            }
        }

        cachedAutoContinueEndAt = nil
        cachedCurrentBlockIndex = nil
        cachedCurrentBlockDisplayNumber = nil
        cachedCurrentBlockStartTime = nil
        cachedCurrentBlockEndTime = nil
        cachedUpcomingBlocks = []
        cachedSessionEndAt = Date()
        currentActivity = nil
    }
    /// Update cached block info when reusing an existing Live Activity for a new block.
    /// Called when auto-continue skips the Live Activity restart — updates the cached
    /// values so subsequent updateLiveActivity calls show the correct block number.
    func updateCachedBlockInfo(blockIndex: Int, isBreak: Bool) {
        let dayStartHour = UserDefaults.standard.object(forKey: "dayStartHour") as? Int ?? 6
        let autoContinueSeconds: TimeInterval = isBreak ? 30 : 25

        cachedCurrentBlockIndex = blockIndex
        cachedCurrentBlockDisplayNumber = BlockTimeUtils.displayBlockNumber(blockIndex, dayStartHour: dayStartHour)
        cachedCurrentBlockStartTime = BlockTimeUtils.blockToTime(blockIndex)
        cachedCurrentBlockEndTime = BlockTimeUtils.blockEndTime(blockIndex)
        cachedAutoContinueEndAt = BlockTimeUtils.blockEndDate(for: blockIndex).addingTimeInterval(autoContinueSeconds)

        // Read check-in limit from settings
        let blocksUntilCheckIn = UserDefaults.standard.object(forKey: "blocksUntilCheckIn") as? Int ?? 3

        // Foreground continuations always start at block boundary (full block), so no partial adjustment
        let upcomingCount = blocksUntilCheckIn

        var upcoming: [UpcomingBlockInfo] = []
        var prevEnd = cachedAutoContinueEndAt!

        for i in 1...upcomingCount {
            let upIndex = blockIndex + i
            guard upIndex < 72 else { break }

            let isLast = (i == upcomingCount)
            let upEndAt = BlockTimeUtils.blockEndDate(for: upIndex)
            let upAcEnd = isLast ? nil : upEndAt.addingTimeInterval(autoContinueSeconds)

            upcoming.append(UpcomingBlockInfo(
                displayNumber: BlockTimeUtils.displayBlockNumber(upIndex, dayStartHour: dayStartHour),
                timerStartAt: prevEnd,
                timerEndAt: upEndAt,
                autoContinueEndAt: upAcEnd
            ))

            prevEnd = upAcEnd ?? upEndAt
        }

        cachedUpcomingBlocks = upcoming
        cachedSessionEndAt = upcoming.last?.timerEndAt ?? BlockTimeUtils.blockEndDate(for: blockIndex)

        print("📱 Updated Live Activity cache for block \(blockIndex) (display: \(cachedCurrentBlockDisplayNumber ?? -1), upcoming: \(upcoming.count))")
    }

    #else
    // Stub methods for Mac Catalyst where Live Activities aren't available
    func startLiveActivity(blockIndex: Int, isBreak: Bool, timerEndAt: Date, timerStartedAt: Date, category: String?, categoryColor: String?, label: String?, progress: Double) async {}
    func updateLiveActivity(timerEndAt: Date, timerStartedAt: Date, category: String?, categoryColor: String?, label: String?, progress: Double, isBreak: Bool) {}
    func updateLiveActivityForAutoContinue(autoContinueEndAt: Date, isBreak: Bool) {}
    func updateCachedBlockInfo(blockIndex: Int, isBreak: Bool) {}
    func endLiveActivity() {}
    #endif
}
