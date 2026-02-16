import SwiftUI
import Combine
import UIKit

struct MainView: View {
    @EnvironmentObject var blockManager: BlockManager
    @EnvironmentObject var timerManager: TimerManager
    @EnvironmentObject var goalManager: GoalManager
    @State private var selectedDate = Date()
    @State private var selectedBlockIndex: Int?
    @State private var showingSettings = false
    @State private var showPlannedBlockDialog = false
    @State private var plannedBlock: Block?
    @State private var dismissedPlannedBlocks: Set<Int> = []
    @State private var lastCheckedBlockIndex: Int = -1
    @State private var showOverview = false
    @State private var blocksWithTimerUsage: Set<Int> = []
    @State private var showDayEndDialog = false
    @State private var continuedPastDayEnd = false
    @State private var showStaleNotificationAlert = false

    private var currentBlockIndex: Int {
        Block.getCurrentBlockIndex()
    }

    @AppStorage("dayStartHour") private var dayStartHour = 6
    @AppStorage("pendingDayStartHour") private var pendingDayStartHour: Int = -1
    @AppStorage("pendingDayStartDateString") private var pendingDayStartDateString: String = ""
    @AppStorage("blocksUntilCheckIn") private var blocksUntilCheckIn = 3

    /// Returns the "logical today" Date, accounting for dayStartHour setting
    /// If current time is before dayStartHour, we're still in "yesterday" (the previous logical day)
    private var logicalToday: Date {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        if currentHour < dayStartHour {
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now
        }
        return now
    }

    /// Returns the "logical today" date string
    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: logicalToday)
    }

    /// Check if selectedDate matches the logical today
    private var isToday: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: selectedDate) == todayString
    }

    private var shouldSuppressAutoContinue: Bool {
        timerManager.blocksSinceLastInteraction >= blocksUntilCheckIn
    }

    /// Count of completed (done) blocks today
    private var completedBlocks: Int {
        blockManager.blocks.filter { $0.status == .done }.count
    }

    var body: some View {
        ZStack {
            // Loading overlay while blocks are loading
            if blockManager.blocks.isEmpty {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading blocks...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }

            // Main content - VStack with sticky header
            VStack(spacing: 0) {
                // STICKY HEADER SECTION
                VStack(spacing: 0) {
                    // Compact header with logo, date nav, settings
                    CompactHeaderView(selectedDate: $selectedDate, showSettings: $showingSettings)

                    // Divider
                    Divider()

                    // Main Goal + Action List (for any day)
                    // Extra padding to align with block colors (not transparent spacing)
                    OneThingView(selectedDate: $selectedDate)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))

                // SCROLLABLE CONTENT
                ScrollView {
                    VStack(spacing: 12) {
                        // Set progress bar
                        SetProgressBarView()
                            .padding(.horizontal, 4)

                        // Block grid - 72 blocks for the day
                        // No extra padding - blocks define the alignment
                        BlockGridView(
                            blocks: blockManager.blocks,
                            date: selectedDate,
                            selectedBlockIndex: $selectedBlockIndex
                        )

                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                .background(Color(.systemBackground))

                // STICKY BOTTOM SECTION - Timer (when active or paused) + Bottom Bar
                // Connected together with no gap
                VStack(spacing: 0) {
                    // FloatingTimerBar handles its own visibility via shouldShow
                    FloatingTimerBar()
                    StickyBottomBar(showOverview: $showOverview)
                }
            }

            // Dialog overlays
            if timerManager.showTimerComplete {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }  // Prevent dismiss on tap

                TimerCompleteDialog(
                    blockIndex: timerManager.currentBlockIndex ?? 0,
                    category: timerManager.currentCategory,
                    label: timerManager.currentLabel,
                    totalDoneBlocks: completedBlocks,
                    timerEndedAt: timerManager.timerCompletedAt ?? Date(),
                    isBreakMode: timerManager.isBreak,
                    suppressAutoContinue: shouldSuppressAutoContinue,
                    isBackgroundCompletion: false,
                    onCheckIn: { timerManager.resetInteractionCounter() },
                    onContinue: {
                        timerManager.resetInteractionCounter()
                        handleContinueWork()
                    },
                    onAutoContinue: {
                        timerManager.incrementInteractionCounter()
                        // After N blocks without user interaction, stop instead of continuing
                        // This prevents "zombie blocks" from filling when user is away
                        if shouldSuppressAutoContinue {
                            handleStop()
                        } else {
                            // Skip Live Activity restart - existing activity already has next block data
                            handleContinueWork(skipLiveActivityRestart: true)
                        }
                    },
                    onTakeBreak: {
                        timerManager.resetInteractionCounter()
                        handleTakeBreak()
                    },
                    onBackToWork: {
                        timerManager.resetInteractionCounter()
                        handleBackToWork()
                    },
                    onStartNewBlock: {
                        timerManager.resetInteractionCounter()
                        handleStartNewBlock()
                    },
                    onSkipNextBlock: handleSkipNextBlock,
                    onStop: {
                        timerManager.resetInteractionCounter()
                        handleStop()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }

            if timerManager.showBreakComplete {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }

                BreakCompleteDialog(
                    blockIndex: timerManager.currentBlockIndex ?? 0,
                    timerEndedAt: timerManager.timerCompletedAt ?? Date(),
                    suppressAutoContinue: false,  // Break popup is mid-block, not block-level — never suppress
                    onCheckIn: nil,
                    onContinueBreak: {
                        // Mid-block break dismissal — don't touch the check-in counter
                        handleContinueBreak()
                    },
                    onAutoContinueBreak: {
                        // Mid-block break auto-dismiss — don't touch the check-in counter
                        handleContinueBreak()
                    },
                    onBackToWork: {
                        timerManager.resetInteractionCounter()
                        handleBackToWork()
                    },
                    onStartNewBlock: {
                        timerManager.resetInteractionCounter()
                        handleStartNewBlock()
                    },
                    onStop: {
                        timerManager.resetInteractionCounter()
                        handleStop()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }

            if showPlannedBlockDialog, let block = plannedBlock {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }

                PlannedBlockDialog(
                    block: block,
                    onStart: { handleStartPlannedBlock(block) },
                    onStartAsBreak: { handleStartPlannedBlockAsBreak(block) },
                    onSkip: { handleSkipPlannedBlock(block) },
                    onDismiss: { handleDismissPlannedBlock(block) }
                )
                .transition(.scale.combined(with: .opacity))
            }

            if showDayEndDialog {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }

                DayEndDialog(
                    onStartNextDay: {
                        showDayEndDialog = false
                        continuedPastDayEnd = false
                        selectedDate = logicalToday
                    },
                    onContinueWorking: {
                        showDayEndDialog = false
                        continuedPastDayEnd = true
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }

            if timerManager.showPausedExpiry {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }

                PausedExpiryDialog(
                    blockIndex: timerManager.currentBlockIndex ?? 0,
                    onContinueWork: {
                        // Save partial data first, then continue (preserves category/label)
                        timerManager.savePartialBlockData()
                        handleContinueWork()  // This calls continueToNextBlock which dismisses the dialog
                    },
                    onTakeBreak: {
                        // Save partial data first, then take break
                        timerManager.savePartialBlockData()
                        handleTakeBreak()  // This calls continueToNextBlock which dismisses the dialog
                    },
                    onStartNewBlock: {
                        // Full dismiss with reset, then open block sheet
                        timerManager.dismissPausedExpiry()
                        selectedBlockIndex = currentBlockIndex
                    },
                    onStop: {
                        // Full dismiss with reset
                        timerManager.dismissPausedExpiry()
                        NotificationManager.shared.cancelAllNotifications()
                        WidgetDataProvider.shared.endLiveActivity()
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: timerManager.showTimerComplete)
        .animation(.easeInOut(duration: 0.2), value: timerManager.showBreakComplete)
        .animation(.easeInOut(duration: 0.2), value: showPlannedBlockDialog)
        .animation(.easeInOut(duration: 0.2), value: showDayEndDialog)
        .animation(.easeInOut(duration: 0.2), value: timerManager.showPausedExpiry)
        // Dialog priority: Timer/Break complete dialogs take precedence over planned dialog
        .onChange(of: timerManager.showTimerComplete) { _, newValue in
            print("📱 DEBUG: showTimerComplete changed to \(newValue)")
            if newValue {
                // Timer complete takes priority over all other dialogs
                if showPlannedBlockDialog {
                    showPlannedBlockDialog = false
                    plannedBlock = nil
                }
                // Dismiss paused expiry - timer complete should never coexist
                if timerManager.showPausedExpiry {
                    timerManager.showPausedExpiry = false
                }
            }
        }
        .onChange(of: timerManager.showBreakComplete) { _, newValue in
            if newValue {
                // Break complete takes priority over other dialogs
                if showPlannedBlockDialog {
                    showPlannedBlockDialog = false
                    plannedBlock = nil
                }
                // Dismiss paused expiry - break complete should never coexist
                if timerManager.showPausedExpiry {
                    timerManager.showPausedExpiry = false
                }
            }
        }
        // Paused expiry takes priority over planned dialog
        .onChange(of: timerManager.showPausedExpiry) { _, newValue in
            if newValue && showPlannedBlockDialog {
                showPlannedBlockDialog = false
                plannedBlock = nil
            }
            // Dismiss paused expiry if timer complete/break complete shows (defensive - shouldn't happen)
            if newValue && (timerManager.showTimerComplete || timerManager.showBreakComplete) {
                timerManager.showPausedExpiry = false
            }
        }
        // Prevent screen from sleeping while timer is active or paused
        .onChange(of: timerManager.isActive) { _, isActive in
            UIApplication.shared.isIdleTimerDisabled = isActive || timerManager.isPaused
        }
        .onChange(of: timerManager.isPaused) { _, isPaused in
            UIApplication.shared.isIdleTimerDisabled = timerManager.isActive || isPaused
        }
        .sheet(isPresented: Binding(
            get: { selectedBlockIndex != nil },
            set: { if !$0 { selectedBlockIndex = nil } }
        )) {
            if let blockIndex = selectedBlockIndex {
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = "yyyy-MM-dd"
                BlockSheetView(blockIndex: blockIndex, date: formatter.string(from: selectedDate))
                    .environmentObject(blockManager)
                    .environmentObject(timerManager)
                    .environmentObject(goalManager)
            }
        }
        .onChange(of: selectedBlockIndex) { oldValue, newValue in
            // When sheet dismisses (newValue is nil), run auto-skip
            if oldValue != nil && newValue == nil && isToday {
                Task {
                    await blockManager.processAutoSkip(currentBlockIndex: currentBlockIndex, timerBlockIndex: timerManager.currentBlockIndex, blocksWithTimerUsage: blocksWithTimerUsage)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(blockManager)
                .environmentObject(timerManager)
                .environmentObject(goalManager)
        }
        .sheet(isPresented: $showOverview) {
            OverviewSheetView()
                .environmentObject(blockManager)
                .environmentObject(timerManager)
                .environmentObject(goalManager)
        }
        .alert("Old Notification", isPresented: $showStaleNotificationAlert) {
            Button("OK") { }
        } message: {
            Text("That notification was for a block that has already ended. Use the app to manage your current session.")
        }
        .onAppear {
            // Initialize selectedDate to logical today (accounting for dayStartHour)
            selectedDate = logicalToday
            // Set initial idle timer state (keep screen on if timer running/paused)
            UIApplication.shared.isIdleTimerDisabled = timerManager.isActive || timerManager.isPaused
        }
        .onDisappear {
            // Re-enable idle timer when view disappears (safety cleanup)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task {
            async let blocksLoad: Void = blockManager.loadBlocks(for: selectedDate)
            async let goalsLoad: Void = goalManager.loadGoals(for: selectedDate)
            _ = await (blocksLoad, goalsLoad)
            setupTimerCallbacks()
            _ = await NotificationManager.shared.requestPermission()
            NotificationManager.shared.setupNotificationCategories()

            // Check for orphaned timer session (app was terminated while timer running)
            // This must run after blocks load but before auto-skip
            await recoverOrphanedTimerSession()

            // Run auto-skip on initial load for today
            if isToday {
                await blockManager.processAutoSkip(currentBlockIndex: currentBlockIndex, timerBlockIndex: timerManager.currentBlockIndex, blocksWithTimerUsage: blocksWithTimerUsage)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // 1. Recover timer state (may trigger completion dialog if timer expired while backgrounded)
            timerManager.restoreFromBackground()

            // 1b. If timer was PAUSED and block time has elapsed, stop it cleanly
            // This treats it as an abandonment - user didn't work during pause
            if timerManager.isPaused,
               let blockIndex = timerManager.currentBlockIndex,
               Block.blockEndDate(for: blockIndex) <= Date() {
                // Block time elapsed while paused - stop without completing
                timerManager.resumeTimer()  // This will detect elapsed time and call stopTimer
            }

            // 2. If check-in grace period (20 min) expired while backgrounded, auto-stop
            if shouldSuppressAutoContinue && timerManager.showTimerComplete,
               let completedAt = timerManager.timerCompletedAt,
               Date().timeIntervalSince(completedAt) > 1200 {
                handleStop()
            }

            // 3. Auto-switch to today if the day has changed, but only when user isn't actively working
            //    and hasn't chosen to continue past day end
            if !isToday && !timerManager.isActive && !timerManager.showTimerComplete && !timerManager.showBreakComplete && !continuedPastDayEnd {
                selectedDate = logicalToday
            }

            // 4. Update widget data on foreground
            WidgetDataProvider.shared.updateWidgetData(
                blocks: blockManager.blocks,
                categories: blockManager.categories,
                timerManager: timerManager,
                goalManager: goalManager
            )

            // 5. Clear badge
            NotificationManager.shared.clearBadge()

            // 6. If user tapped a notification action, execute it now
            //    (this dismisses any dialog that restoreFromBackground showed)
            if let action = NotificationManager.shared.pendingAction {
                let notificationBlockIndex = NotificationManager.shared.pendingActionBlockIndex
                print("📲 Processing notification action: \(action) for block \(notificationBlockIndex ?? -1), current block: \(currentBlockIndex)")
                NotificationManager.shared.pendingAction = nil
                NotificationManager.shared.pendingActionBlockIndex = nil

                // Check if this is a stale notification (from a past block)
                // Notifications fire at the END of a block, and their actions affect the NEXT block.
                // e.g., notification for block 32 fires at 11:00, actions start block 33
                // So the notification is valid while we're in block 33 (notifBlock + 1 == currentBlock)
                // It's only stale when block 33 has ALSO passed (notifBlock + 1 < currentBlock)
                let isStaleNotification: Bool = {
                    guard let notifBlock = notificationBlockIndex else { return false }
                    // Stale if the NEXT block after the notification has also passed
                    return notifBlock + 1 < currentBlockIndex
                }()

                if isStaleNotification {
                    // Stale notification - just show an alert, don't take any action
                    // This prevents old notifications from affecting the current timer state
                    print("📲 Ignoring stale notification action from block \(notificationBlockIndex ?? -1)")

                    // Only clean up if there's nothing actively running
                    // If timer is running or a dialog is showing, leave everything as-is
                    // so the user can interact with the current state
                    if !timerManager.isActive && !timerManager.isPaused &&
                       !timerManager.showTimerComplete && !timerManager.showBreakComplete {
                        // Nothing active - safe to clean up any orphaned state
                        NotificationManager.shared.cancelAllNotifications()
                        WidgetDataProvider.shared.endLiveActivity()
                    }

                    // Show alert to explain why the action was ignored
                    showStaleNotificationAlert = true
                } else {
                    // Valid notification - process the action
                    // User explicitly tapped a notification action — reset check-in counter
                    timerManager.resetInteractionCounter()
                    switch action {
                    case "continue":
                        handleContinueWork()
                    case "takeBreak": handleTakeBreak()
                    case "newBlock":
                        timerManager.dismissTimerComplete()
                        timerManager.dismissBreakComplete()
                        WidgetDataProvider.shared.endLiveActivity()
                        // Open the blocksheet for the current block
                        selectedBlockIndex = currentBlockIndex
                    case "stop": handleStop()
                    default: break
                    }
                }
            } else {
                // 6b. No notification action — user just opened the app.
                //     Check if auto-continue should have already fired while backgrounded.
                //     If multiple blocks have passed, retroactively fill them.
                if timerManager.showTimerComplete, let completedAt = timerManager.timerCompletedAt {
                    let timeSinceCompletion = Date().timeIntervalSince(completedAt)
                    let autoContinueSeconds: TimeInterval = 25

                    if timeSinceCompletion >= autoContinueSeconds {
                        // Auto-continue period has passed — process retroactive auto-continues
                        // CRITICAL: Hide dialog FIRST to prevent race with dialog's onAutoContinue
                        // The dialog's onAppear fires immediately when completedAt is far in the past
                        timerManager.showTimerComplete = false
                        Task {
                            await processRetroactiveAutoContinues(
                                completedAt: completedAt,
                                autoContinueDelay: autoContinueSeconds,
                                isBreak: false
                            )
                        }
                    } else {
                        // Still within auto-continue period — show dialog with REMAINING time
                        let remainingTime = autoContinueSeconds - timeSinceCompletion
                        let autoContinueEndAt = Date().addingTimeInterval(remainingTime)
                        WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                            autoContinueEndAt: autoContinueEndAt,
                            isBreak: false
                        )
                    }
                } else if timerManager.showBreakComplete, let completedAt = timerManager.timerCompletedAt {
                    let timeSinceCompletion = Date().timeIntervalSince(completedAt)
                    let autoContinueSeconds: TimeInterval = 30

                    if timeSinceCompletion >= autoContinueSeconds {
                        // Break auto-continue period has passed — process retroactive auto-continues
                        // CRITICAL: Hide dialog FIRST to prevent race with dialog's onAutoContinue
                        timerManager.showBreakComplete = false
                        Task {
                            await processRetroactiveAutoContinues(
                                completedAt: completedAt,
                                autoContinueDelay: autoContinueSeconds,
                                isBreak: true
                            )
                        }
                    } else {
                        // Still within break auto-continue period
                        let remainingTime = autoContinueSeconds - timeSinceCompletion
                        let autoContinueEndAt = Date().addingTimeInterval(remainingTime)
                        WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                            autoContinueEndAt: autoContinueEndAt,
                            isBreak: true
                        )
                    }
                }
            }

            // 7. Clean up orphaned Live Activities if timer is not running
            if !timerManager.isActive && !timerManager.isPaused && !timerManager.showTimerComplete && !timerManager.showBreakComplete {
                WidgetDataProvider.shared.endLiveActivity()
            }

            // 8. Reload blocks, goals, and auto-skip
            if isToday {
                Task {
                    await blockManager.reloadBlocks()
                    await goalManager.loadGoals(for: selectedDate)
                    await blockManager.processAutoSkip(currentBlockIndex: currentBlockIndex, timerBlockIndex: timerManager.currentBlockIndex, blocksWithTimerUsage: blocksWithTimerUsage)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            timerManager.saveStateForBackground()
            // Persist widget data for widget access while backgrounded
            WidgetDataProvider.shared.updateWidgetData(
                blocks: blockManager.blocks,
                categories: blockManager.categories,
                timerManager: timerManager,
                goalManager: goalManager
            )
        }
        .onChange(of: selectedDate) { _, newDate in
            Task {
                async let blocksLoad: Void = blockManager.loadBlocks(for: newDate)
                async let goalsLoad: Void = goalManager.loadGoals(for: newDate)
                _ = await (blocksLoad, goalsLoad)
            }
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            // Check every 10 seconds for block changes to catch transitions faster
            // This ensures blocks get marked as done promptly after their time passes
            checkForBlockChange()
            // Check if pending dayStartHour change should be applied
            checkPendingDayStartHourChange()
        }
    }

    // MARK: - Timer Callbacks

    private func setupTimerCallbacks() {
        timerManager.onTimerComplete = { blockIndex, date, isBreak, secondsUsed, initialTime, segments, visualFill in
            // Track this block as having timer usage
            self.blocksWithTimerUsage.insert(blockIndex)

            // Determine if this was a natural completion (timer hit 0) vs manual stop
            // Natural completion: secondsUsed == initialTime (timer ran to block boundary)
            // Use 5-second tolerance for timer tick timing jitter
            let isNaturalCompletion = secondsUsed >= initialTime - 5

            // Also check actual time in case of edge cases
            let blockEnd = Block.blockEndDate(for: blockIndex)
            let blockTimeElapsed = Date() >= blockEnd

            // Mark done if timer ran to completion OR block time has passed
            let shouldMarkDone = isNaturalCompletion || blockTimeElapsed

            // IMMEDIATELY update local state (synchronous, no race condition)
            // Fill is determined by visualFill, not status (so partial fills display correctly)
            let actualProgress = min(100.0, Double(secondsUsed) / 1200.0 * 100.0)
            if let idx = self.blockManager.blocks.firstIndex(where: { $0.blockIndex == blockIndex }) {
                if shouldMarkDone {
                    self.blockManager.blocks[idx].status = .done
                    print("✅ Marked block \(blockIndex) as .done (natural: \(isNaturalCompletion), elapsed: \(blockTimeElapsed)), progress: \(Int(actualProgress))%, visualFill: \(Int(visualFill * 100))%")
                } else {
                    print("💾 Saved block \(blockIndex) segments (block still active), progress: \(Int(actualProgress))%, visualFill: \(Int(visualFill * 100))%")
                }
                self.blockManager.blocks[idx].segments = BlockSegment.normalized(segments)
                self.blockManager.blocks[idx].usedSeconds = secondsUsed
                self.blockManager.blocks[idx].progress = actualProgress
                self.blockManager.blocks[idx].visualFill = visualFill
            }
            Task {
                await self.saveTimerCompletion(blockIndex: blockIndex, date: date, secondsUsed: secondsUsed, initialTime: initialTime, segments: segments, visualFill: visualFill, blockTimeElapsed: shouldMarkDone)
            }
        }

        timerManager.onSaveSnapshot = { blockIndex, date, snapshot in
            Task {
                await saveSnapshot(blockIndex: blockIndex, date: date, snapshot: snapshot)
            }
        }

        // Widget update callback: called on timer start/stop/complete, category change, progress milestones
        timerManager.onWidgetUpdate = { [self] in
            WidgetDataProvider.shared.updateWidgetData(
                blocks: blockManager.blocks,
                categories: blockManager.categories,
                timerManager: timerManager,
                goalManager: goalManager
            )
            // Update Live Activity state
            if timerManager.isActive, let endAt = timerManager.exposedEndAt, let startedAt = timerManager.exposedStartedAt {
                let categoryColor = blockManager.categories.first { $0.id == timerManager.currentCategory }?.color
                WidgetDataProvider.shared.updateLiveActivity(
                    timerEndAt: endAt,
                    timerStartedAt: startedAt,
                    category: timerManager.currentCategory,
                    categoryColor: categoryColor,
                    label: timerManager.currentLabel,
                    progress: timerManager.progressPercent / 100.0,
                    isBreak: timerManager.isBreak
                )
            }
            // NOTE: Don't call updateLiveActivityForAutoContinue here - it wipes out the next block info
            // that was set in startLiveActivity. The Live Activity's TimelineView handles phase
            // transitions autonomously using the pre-set dates (timerEndAt, autoContinueEndAt,
            // nextBlockTimerEndAt, nextBlockAutoContinueEndAt).
        }

        // Blocks changed callback: called on load/save/reload
        blockManager.onBlocksChanged = { [self] in
            WidgetDataProvider.shared.updateWidgetData(
                blocks: blockManager.blocks,
                categories: blockManager.categories,
                timerManager: timerManager,
                goalManager: goalManager
            )
        }

        // Categories changed callback: called when category colors/names are updated
        blockManager.onCategoriesChanged = { [self] in
            // Update widget data
            WidgetDataProvider.shared.updateWidgetData(
                blocks: blockManager.blocks,
                categories: blockManager.categories,
                timerManager: timerManager,
                goalManager: goalManager
            )

            // Also update Live Activity if timer is running (so color changes reflect immediately)
            if timerManager.isActive, let endAt = timerManager.exposedEndAt, let startedAt = timerManager.exposedStartedAt {
                let categoryColor = blockManager.categories.first { $0.id == timerManager.currentCategory }?.color
                WidgetDataProvider.shared.updateLiveActivity(
                    timerEndAt: endAt,
                    timerStartedAt: startedAt,
                    category: blockManager.categories.first { $0.id == timerManager.currentCategory }?.label ?? timerManager.currentCategory,
                    categoryColor: categoryColor,
                    label: timerManager.currentLabel,
                    progress: timerManager.progress,
                    isBreak: timerManager.isBreak
                )
            }
        }
    }

    private func saveTimerCompletion(blockIndex: Int, date: String, secondsUsed: Int, initialTime: Int, segments: [BlockSegment], visualFill: Double, blockTimeElapsed: Bool) async {
        guard let block = blockManager.blocks.first(where: { $0.blockIndex == blockIndex }) else {
            print("⚠️ saveTimerCompletion: block \(blockIndex) not found in local array, skipping DB save")
            return
        }

        // Calculate progress based on actual time used vs block duration
        let blockDurationSeconds = 20 * 60  // 1200 seconds
        let actualProgress = min(100.0, Double(secondsUsed) / Double(blockDurationSeconds) * 100.0)

        var updatedBlock = block
        updatedBlock.usedSeconds = secondsUsed
        updatedBlock.progress = actualProgress
        updatedBlock.visualFill = visualFill  // Save actual visual fill reached

        // Only mark as done if block time has elapsed
        // User might stop mid-block and resume later in the same block window
        if blockTimeElapsed {
            updatedBlock.status = .done
        }
        updatedBlock.category = timerManager.currentCategory ?? block.category
        updatedBlock.label = timerManager.currentLabel ?? block.label

        // Use the segments passed from the callback (captured before clearing)
        // Normalize to merge consecutive same-type/category/label segments (prevents micro-segment clutter)
        updatedBlock.segments = BlockSegment.normalized(segments)

        print("💾 saveTimerCompletion: block \(blockIndex), used \(secondsUsed)s, progress \(Int(actualProgress))%, visualFill: \(Int(visualFill * 100))%, segments: \(segments.count), done: \(blockTimeElapsed)")

        await blockManager.saveBlock(updatedBlock)
        await blockManager.reloadBlocks()
    }

    private func saveSnapshot(blockIndex: Int, date: String, snapshot: Run) async {
        // Don't save if user has clicked Stop on notification but it hasn't been processed yet
        // This prevents the autosave timer from saving stale data after the user intended to stop
        if NotificationManager.shared.pendingAction == "stop" {
            print("💾 saveSnapshot: Skipping - stop action pending")
            return
        }

        guard let block = blockManager.blocks.first(where: { $0.blockIndex == blockIndex }) else {
            print("💾 saveSnapshot: Block \(blockIndex) not found")
            return
        }

        // Calculate totals from previous segments + current snapshot segments
        let previousSegments = timerManager.previousSegments
        let allSegments = previousSegments + snapshot.segments

        // Calculate used seconds and progress
        let totalUsedSeconds = allSegments.reduce(0) { $0 + $1.seconds }
        let totalWorkSeconds = allSegments.filter { $0.type == .work }.reduce(0) { $0 + $1.seconds }
        let totalBreakSeconds = allSegments.filter { $0.type == .break }.reduce(0) { $0 + $1.seconds }

        let blockDurationSeconds = 20 * 60  // 1200 seconds
        let newProgress = min(100.0, Double(totalWorkSeconds) / Double(blockDurationSeconds) * 100.0)
        let newBreakProgress = min(100.0, Double(totalBreakSeconds) / Double(blockDurationSeconds) * 100.0)

        var updatedBlock = block
        updatedBlock.activeRunSnapshot = snapshot
        updatedBlock.usedSeconds = totalUsedSeconds
        updatedBlock.progress = newProgress
        updatedBlock.breakProgress = newBreakProgress
        // Save current visual fill so it persists correctly if app crashes or block is auto-marked done
        updatedBlock.visualFill = timerManager.currentVisualFill
        // During break, don't overwrite the block's category/label with the
        // timer's stale work values — the block should keep whatever was set
        // when work was active. Only update during work mode.
        if !timerManager.isBreak {
            updatedBlock.category = timerManager.currentCategory ?? block.category
            updatedBlock.label = timerManager.currentLabel ?? block.label
        }
        // Also save the combined segments so they persist on refresh
        // Normalize to merge consecutive same-type/category/label segments (prevents micro-segment clutter)
        updatedBlock.segments = BlockSegment.normalized(allSegments)

        await blockManager.saveBlock(updatedBlock)
        print("💾 Saved snapshot for block \(blockIndex) - usedSeconds: \(totalUsedSeconds), progress: \(Int(newProgress))%, visualFill: \(String(format: "%.1f%%", timerManager.currentVisualFill * 100))")
    }

    /// When auto-continuing across a day boundary, flip the grid to the new day.
    private func flipToNextDayIfGridWrapped(nextBlockIndex: Int) async {
        guard !isToday else { return }
        // Day has changed — switch grid to new day
        print("📅 Day changed — flipping grid to logical today")
        continuedPastDayEnd = false
        selectedDate = logicalToday
        await blockManager.loadBlocks(for: selectedDate)
        await goalManager.loadGoals(for: selectedDate)
    }

    private func saveBlockForContinue(blockIndex: Int, category: String?, label: String?) async {
        print("🔄 saveBlockForContinue: block \(blockIndex), category: \(category ?? "nil"), label: \(label ?? "nil")")

        // Find or create the block for the continued work
        if let block = blockManager.blocks.first(where: { $0.blockIndex == blockIndex }) {
            print("🔄 Found existing block, updating...")
            var updatedBlock = block
            updatedBlock.category = category
            updatedBlock.label = label
            // Don't change status — the timer is about to start on this block.
            // onTimerComplete will mark it .done when it finishes.
            // Mark as activated (hides moon icon in Night segment)
            updatedBlock.isActivated = true
            updatedBlock.updatedAt = ISO8601DateFormatter().string(from: Date())
            await blockManager.saveBlock(updatedBlock)
            print("🔄 Block updated successfully")
        } else {
            // Block doesn't exist yet, create it
            print("🔄 Block doesn't exist, creating new one...")
            // Get userId from existing blocks or auth manager
            let userId = blockManager.blocks.first?.userId ?? ""
            if userId.isEmpty {
                print("⚠️ Warning: No userId found!")
            }
            let newBlock = Block(
                id: UUID().uuidString,
                userId: userId,
                date: todayString,
                blockIndex: blockIndex,
                isMuted: false,
                isActivated: true,
                category: category,
                label: label,
                note: nil,
                status: .idle,
                progress: 0,
                breakProgress: 0,
                runs: nil,
                activeRunSnapshot: nil,
                segments: [],
                usedSeconds: 0,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            await blockManager.saveBlock(newBlock)
            print("🔄 New block created")
        }
        // NOTE: Do NOT call reloadBlocks() here - saveBlock already updates the local array
        // Calling reloadBlocks() triggers a SwiftUI re-render cycle that can cause
        // the timer to restart in a loop (the continuation handler gets re-triggered)
    }

    // MARK: - Widget / Live Activity Helpers

    private func startWidgetLiveActivity(blockIndex: Int, isBreak: Bool, endAt: Date, category: String?, label: String?) {
        let categoryColor = blockManager.categories.first { $0.id == category }?.color
        let timeUntilEnd = endAt.timeIntervalSinceNow
        print("📱 Starting Live Activity: block \(blockIndex), endAt = \(endAt), timeUntilEnd = \(String(format: "%.0f", timeUntilEnd))s (\(timeUntilEnd > 0 ? "FUTURE ✓" : "PAST ⚠️"))")

        // Wrap in Task since startLiveActivity is now async
        // This ensures old activities are fully ended before new one starts (prevents duplicates)
        Task {
            await WidgetDataProvider.shared.startLiveActivity(
                blockIndex: blockIndex,
                isBreak: isBreak,
                timerEndAt: endAt,
                timerStartedAt: Date(),
                category: category,
                categoryColor: categoryColor,
                label: label,
                progress: 0
            )
        }
    }

    // MARK: - Dialog Actions

    private func handleContinueWork(skipLiveActivityRestart: Bool = false) {
        // ALWAYS continue on the CURRENT TIME block
        // The timer completed at the block boundary, so the current block IS the next one
        // If the user waited before clicking, we still go to wherever "now" is
        // NEVER start a timer on a future block
        let actualCurrentBlock = Block.getCurrentBlockIndex()
        let nextBlockIndex = actualCurrentBlock
        let blockEndAt = Block.blockEndDate(for: nextBlockIndex)
        print("📱 handleContinueWork: continuing to block \(nextBlockIndex), blockEndAt = \(blockEndAt), timeUntilEnd = \(String(format: "%.0f", blockEndAt.timeIntervalSinceNow))s")
        blocksWithTimerUsage.insert(nextBlockIndex)

        // GUARD: Don't restart if timer is already running on this block
        if timerManager.isActive && timerManager.currentBlockIndex == nextBlockIndex {
            print("⚠️ handleContinueWork: Timer already active on block \(nextBlockIndex), skipping")
            return
        }

        guard nextBlockIndex < 72 else {
            handleStop()
            return
        }

        // If the user was on a break when the block ended, continue as a break
        // (same logic as any other category leaking into the next block)
        let wasBreak = timerManager.isBreak
        let category = wasBreak ? nil : timerManager.currentCategory
        let label = wasBreak ? "Break" : timerManager.currentLabel

        // Get existing segments from next block (in case it has data from earlier)
        // BUT if we're crossing a day boundary, use empty segments (new day = fresh block)
        let existingSegments: [BlockSegment]
        if isToday {
            let nextBlock = blockManager.blocks.first { $0.blockIndex == nextBlockIndex }
            existingSegments = nextBlock?.segments ?? []
        } else {
            // Day boundary crossed - new day's block is fresh, no existing segments
            existingSegments = []
        }

        timerManager.continueToNextBlock(
            nextBlockIndex: nextBlockIndex,
            date: todayString,
            isBreakMode: wasBreak,
            category: category,
            label: label,
            existingSegments: existingSegments
        )

        // Start Live Activity (skip during auto-continue - existing activity handles it)
        if !skipLiveActivityRestart {
            startWidgetLiveActivity(
                blockIndex: nextBlockIndex,
                isBreak: wasBreak,
                endAt: Block.blockEndDate(for: nextBlockIndex),
                category: category,
                label: label
            )
        } else {
            print("📱 Skipping Live Activity restart - existing activity continues autonomously")
        }

        // Activate and save the block - this handles unmuting and auto-skipping previous muted blocks
        // NOTE: flipToNextDayIfGridWrapped runs FIRST to ensure blocks are loaded for the correct day
        // before activateBlockForTimer and saveBlockForContinue operate on them
        Task {
            await flipToNextDayIfGridWrapped(nextBlockIndex: nextBlockIndex)
            await blockManager.activateBlockForTimer(blockIndex: nextBlockIndex)
            await saveBlockForContinue(blockIndex: nextBlockIndex, category: category, label: label)
        }

        // Schedule notification — break gets 5-min reminder, work gets block boundary
        let willCheckIn = timerManager.blocksSinceLastInteraction >= blocksUntilCheckIn - 1
        if wasBreak {
            NotificationManager.shared.scheduleTimerComplete(
                at: Date().addingTimeInterval(300),
                blockIndex: nextBlockIndex,
                isBreak: true,
                isCheckIn: willCheckIn
            )
        } else {
            NotificationManager.shared.scheduleTimerComplete(
                at: Block.blockEndDate(for: nextBlockIndex),
                blockIndex: nextBlockIndex,
                isBreak: false,
                isCheckIn: willCheckIn
            )
        }

        // Trigger segment focus change (handles collapse/expand/scroll)
        NotificationCenter.default.post(name: .segmentFocusChanged, object: nil)
    }

    private func handleTakeBreak() {
        // Always use the actual current time block for break
        let blockIndex = Block.getCurrentBlockIndex()
        blocksWithTimerUsage.insert(blockIndex)

        // Get existing segments from this block (in case it has data from earlier)
        let targetBlock = blockManager.blocks.first { $0.blockIndex == blockIndex }
        let existingSegments = targetBlock?.segments ?? []

        timerManager.continueToNextBlock(
            nextBlockIndex: blockIndex,
            date: todayString,
            isBreakMode: true,
            category: nil,
            label: "Break",
            existingSegments: existingSegments
        )

        // Start Live Activity — break timer runs to block boundary
        startWidgetLiveActivity(
            blockIndex: blockIndex,
            isBreak: true,
            endAt: Block.blockEndDate(for: blockIndex),
            category: nil,
            label: "Break"
        )

        // Schedule notification for break reminder (5 minutes, not block end)
        NotificationManager.shared.scheduleTimerComplete(
            at: Date().addingTimeInterval(300),
            blockIndex: blockIndex,
            isBreak: true
        )
    }

    private func handleStartNewBlock() {
        // Stop the timer if still running (e.g., mid-block break notification)
        if timerManager.isActive {
            timerManager.stopTimer(markComplete: false)
        }
        timerManager.dismissTimerComplete()
        timerManager.dismissBreakNotification()
        WidgetDataProvider.shared.endLiveActivity()
        // Open block selection sheet for current block
        selectedBlockIndex = currentBlockIndex
    }

    private func handleContinueBreak() {
        // Dismiss the break popup — break continues to block boundary with no more popups.
        // The 5-min reminder fires once per break session. After "Keep Resting", the break
        // runs like any normal category until the block ends or the user switches back to work.
        timerManager.dismissBreakNotification()
    }

    private func handleBackToWork() {
        // If timer is still active in break mode (mid-block break notification),
        // just switch to work mode — no need to restart the timer
        if timerManager.isActive && timerManager.isBreak {
            timerManager.switchToWork()
            timerManager.dismissBreakNotification()

            // Schedule notification at block boundary for work completion
            if let blockIndex = timerManager.currentBlockIndex {
                NotificationManager.shared.scheduleTimerComplete(
                    at: Block.blockEndDate(for: blockIndex),
                    blockIndex: blockIndex,
                    isBreak: false
                )
                // Update Live Activity to show work mode
                let category = timerManager.currentCategory
                startWidgetLiveActivity(
                    blockIndex: blockIndex,
                    isBreak: false,
                    endAt: Block.blockEndDate(for: blockIndex),
                    category: category,
                    label: timerManager.currentLabel
                )
            }
            return
        }

        // Timer is NOT active (block boundary completion) — start a new work timer
        let actualCurrentBlock = Block.getCurrentBlockIndex()

        // GUARD: Don't restart if timer is already running work on this block
        if timerManager.isActive && !timerManager.isBreak && timerManager.currentBlockIndex == actualCurrentBlock {
            print("⚠️ handleBackToWork: Work timer already active on block \(actualCurrentBlock), skipping")
            return
        }

        guard actualCurrentBlock < 72 else {
            handleStop()
            return
        }

        let nextBlockIndex = actualCurrentBlock
        blocksWithTimerUsage.insert(nextBlockIndex)

        // Use preserved pre-break work context (lastWorkCategory/lastWorkLabel)
        // Fall back to currentCategory/currentLabel if not in break mode
        let category = timerManager.lastWorkCategory ?? timerManager.currentCategory
        let label = timerManager.lastWorkLabel ?? timerManager.currentLabel

        // Get existing segments from next block (in case it has data from earlier)
        // BUT if we're crossing a day boundary, use empty segments (new day = fresh block)
        let existingSegments: [BlockSegment]
        if isToday {
            let nextBlock = blockManager.blocks.first { $0.blockIndex == nextBlockIndex }
            existingSegments = nextBlock?.segments ?? []
        } else {
            // Day boundary crossed - new day's block is fresh, no existing segments
            existingSegments = []
        }

        timerManager.continueToNextBlock(
            nextBlockIndex: nextBlockIndex,
            date: todayString,
            isBreakMode: false,
            category: category,
            label: label,
            existingSegments: existingSegments
        )

        // Start Live Activity
        startWidgetLiveActivity(
            blockIndex: nextBlockIndex,
            isBreak: false,
            endAt: Block.blockEndDate(for: nextBlockIndex),
            category: category,
            label: label
        )

        // Activate and save the block - this handles unmuting and auto-skipping previous muted blocks
        // NOTE: flipToNextDayIfGridWrapped runs FIRST to ensure blocks are loaded for the correct day
        // before activateBlockForTimer and saveBlockForContinue operate on them
        Task {
            await flipToNextDayIfGridWrapped(nextBlockIndex: nextBlockIndex)
            await blockManager.activateBlockForTimer(blockIndex: nextBlockIndex)
            await saveBlockForContinue(blockIndex: nextBlockIndex, category: category, label: label)
        }

        // Schedule notification at next block's end time
        NotificationManager.shared.scheduleTimerComplete(
            at: Block.blockEndDate(for: nextBlockIndex),
            blockIndex: nextBlockIndex,
            isBreak: false
        )

        // Trigger segment focus change (handles collapse/expand/scroll)
        NotificationCenter.default.post(name: .segmentFocusChanged, object: nil)
    }

    private func handleStop() {
        print("🛑 handleStop called - isActive: \(timerManager.isActive), showTimerComplete: \(timerManager.showTimerComplete), showBreakComplete: \(timerManager.showBreakComplete)")
        // Stop the timer if still running (e.g., mid-block break notification)
        if timerManager.isActive {
            timerManager.stopTimer(markComplete: false)
        }
        // Also dismiss paused expiry if shown
        if timerManager.showPausedExpiry {
            timerManager.dismissPausedExpiry()
        }
        timerManager.dismissTimerComplete()
        timerManager.dismissBreakComplete()
        NotificationManager.shared.cancelAllNotifications()
        WidgetDataProvider.shared.endLiveActivity()

        // Run auto-skip immediately to mark past blocks with usage as done
        // This ensures blocks stopped near their end time get properly marked
        if isToday {
            Task {
                await blockManager.processAutoSkip(
                    currentBlockIndex: currentBlockIndex,
                    timerBlockIndex: nil,  // Timer is stopped, no active block
                    blocksWithTimerUsage: blocksWithTimerUsage
                )
            }
        }
        print("🛑 handleStop complete - timer stopped and all dialogs dismissed")
    }

    /// Recover from app termination while timer was running (cold launch recovery).
    /// Checks for blocks with activeRunSnapshot and finalizes them if their time has passed.
    private func recoverOrphanedTimerSession() async {
        // Only check today's blocks - past days' orphaned sessions are handled by auto-skip
        guard isToday else { return }

        // Find block with an active (non-ended) snapshot
        guard let orphanedBlock = blockManager.blocks.first(where: { block in
            guard let snapshot = block.activeRunSnapshot else { return false }
            // Snapshot is orphaned if endedAt is nil (timer was running when app died)
            return snapshot.endedAt == nil
        }) else {
            return
        }

        guard let snapshot = orphanedBlock.activeRunSnapshot else { return }

        let blockEndTime = Block.blockEndDate(for: orphanedBlock.blockIndex)
        let now = Date()

        print("🔄 Found orphaned timer session on block \(orphanedBlock.blockIndex), blockEndTime=\(blockEndTime), now=\(now)")

        // Only process if this block's time has passed
        guard now > blockEndTime else {
            print("🔄 Orphaned block \(orphanedBlock.blockIndex) is still current - will be handled by normal timer flow")
            return
        }

        // Block time has passed - finalize it as complete
        // The snapshot contains segments up to when the app was terminated
        // We should credit the full block since timer was meant to run to boundary
        let snapshotSegments = snapshot.segments
        let lastSegmentType = snapshotSegments.last?.type ?? .work
        let lastCategory = snapshotSegments.last(where: { $0.type == .work })?.category ?? orphanedBlock.category
        let lastLabel = snapshotSegments.last(where: { $0.type == .work })?.label ?? orphanedBlock.label

        // Calculate how much time the snapshot captured
        let snapshotSeconds = snapshotSegments.reduce(0) { $0 + $1.seconds }

        // The timer was meant to run to block boundary - credit the remaining time
        // (This handles the case where app died mid-timer)
        let blockDuration = 1200 // 20 minutes
        let remainingSeconds = max(0, blockDuration - snapshotSeconds)

        var finalSegments = snapshotSegments
        if remainingSeconds > 0 {
            // Add the remaining time as a final segment (same type as last segment)
            let finalSegment = BlockSegment(
                type: lastSegmentType,
                seconds: remainingSeconds,
                category: lastSegmentType == .work ? lastCategory : nil,
                label: lastSegmentType == .work ? lastLabel : nil,
                startElapsed: snapshotSeconds
            )
            finalSegments.append(finalSegment)
        }

        // Normalize and save the block as done
        var updatedBlock = orphanedBlock
        updatedBlock.segments = BlockSegment.normalized(finalSegments)
        updatedBlock.status = .done
        updatedBlock.usedSeconds = finalSegments.reduce(0) { $0 + $1.seconds }
        updatedBlock.visualFill = 1.0  // Full block
        updatedBlock.activeRunSnapshot = nil  // Clear the snapshot
        updatedBlock.progress = Double(updatedBlock.segments.filter { $0.type == .work }.reduce(0) { $0 + $1.seconds }) / 12.0

        await blockManager.saveBlock(updatedBlock)
        print("✅ Recovered orphaned block \(orphanedBlock.blockIndex) - credited \(remainingSeconds)s additional time, total \(updatedBlock.usedSeconds)s")

        // Now trigger auto-continue to current block if applicable
        let currentWallClockBlock = Block.getCurrentBlockIndex()

        // Don't auto-continue if too many blocks have passed (check-in threshold)
        let blocksPassed = currentWallClockBlock - orphanedBlock.blockIndex
        if blocksPassed > blocksUntilCheckIn {
            print("🔄 Too many blocks passed (\(blocksPassed)) since orphaned block - not auto-continuing")
            return
        }

        // Fill any intermediate blocks and continue to current
        if currentWallClockBlock > orphanedBlock.blockIndex + 1 {
            // Multiple blocks passed - fill intermediates
            for blockIdx in (orphanedBlock.blockIndex + 1)..<currentWallClockBlock {
                await markBlockAsAutoFilled(
                    blockIndex: blockIdx,
                    category: lastCategory,
                    label: lastLabel,
                    isBreak: lastSegmentType == .break
                )
            }
        }

        // Start timer on current block (auto-continue)
        if currentWallClockBlock < 72 && !shouldSuppressAutoContinue {
            print("🔄 Auto-continuing to block \(currentWallClockBlock) after orphaned session recovery")
            timerManager.incrementInteractionCounter()
            handleContinueWork()
        }
    }

    /// Process retroactive auto-continues when app returns to foreground after being away.
    /// This fills intermediate blocks that would have auto-continued while backgrounded.
    private func processRetroactiveAutoContinues(completedAt: Date, autoContinueDelay: TimeInterval, isBreak: Bool) async {
        // Get the block that originally completed (still available in timerManager after handleTimerComplete)
        guard let originalBlockIndex = timerManager.currentBlockIndex else {
            print("⚠️ processRetroactiveAutoContinues: No original block index, falling back to single auto-continue")
            if shouldSuppressAutoContinue {
                handleStop()
            } else {
                timerManager.incrementInteractionCounter()
                handleContinueWork()
            }
            return
        }

        let currentWallClockBlock = Block.getCurrentBlockIndex()

        // The original block already completed and was saved by handleTimerComplete.
        // Now we need to fill any intermediate blocks that would have auto-continued.

        // If we're still on the same block, just do a simple auto-continue
        if currentWallClockBlock == originalBlockIndex + 1 {
            // Only one block has passed
            if shouldSuppressAutoContinue {
                // Check-in limit already reached - show check-in dialog with grace period
                let checkInTriggeredAt = completedAt  // The original block completion triggered check-in
                let gracePeriod: TimeInterval = 20 * 60  // 20 minutes
                let timeSinceCheckIn = Date().timeIntervalSince(checkInTriggeredAt)

                if timeSinceCheckIn >= gracePeriod {
                    handleStop()
                } else {
                    // Send notification and show check-in dialog
                    let graceMinutesRemaining = Int((gracePeriod - timeSinceCheckIn) / 60)

                    NotificationManager.shared.scheduleCheckInNotification(
                        blockIndex: currentWallClockBlock,
                        graceMinutesRemaining: max(1, graceMinutesRemaining)
                    )

                    timerManager.showTimerComplete = true
                    timerManager.timerCompletedAt = checkInTriggeredAt
                    let graceEndAt = checkInTriggeredAt.addingTimeInterval(gracePeriod)
                    WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                        autoContinueEndAt: graceEndAt,
                        isBreak: isBreak
                    )
                }
            } else {
                timerManager.incrementInteractionCounter()
                handleContinueWork()
            }
            return
        }

        // Multiple blocks have passed - need to fill intermediate blocks
        let category = timerManager.currentCategory
        let label = timerManager.currentLabel
        var blocksAutoFilled = 0
        let limit = blocksUntilCheckIn

        print("📱 processRetroactiveAutoContinues: original block \(originalBlockIndex), current \(currentWallClockBlock), limit \(limit)")

        // Fill blocks from (originalBlockIndex + 1) up to (currentWallClockBlock - 1)
        // These are complete blocks that auto-continued and ran their full duration
        for blockIdx in (originalBlockIndex + 1)..<currentWallClockBlock {
            // Check if we've hit the check-in limit
            if timerManager.blocksSinceLastInteraction + blocksAutoFilled >= limit {
                print("📱 Check-in limit reached after \(blocksAutoFilled) retroactive blocks")
                break
            }

            // Calculate when this block would have started (after auto-continue delay)
            // Each block starts 25s after the previous one ended
            // Block N ends at its block boundary, Block N+1 starts 25s later
            let blockEndTime = Block.blockEndDate(for: blockIdx)

            // Only fill if we're past this block's end time
            if Date() > blockEndTime {
                await markBlockAsAutoFilled(
                    blockIndex: blockIdx,
                    category: category,
                    label: label,
                    isBreak: isBreak
                )
                blocksAutoFilled += 1
                timerManager.incrementInteractionCounter()
                print("📱 Retroactively filled block \(blockIdx)")
            }
        }

        // Reload blocks to update UI before handling current block
        // This prevents the flash of incomplete blocks
        if blocksAutoFilled > 0 {
            await blockManager.reloadBlocks()
        }

        // Now handle the current block
        if timerManager.blocksSinceLastInteraction >= limit {
            // Check-in limit reached - give user a grace period before stopping
            // Calculate when the check-in was triggered (when the last auto-filled block ended)
            let lastFilledBlockIndex = originalBlockIndex + blocksAutoFilled
            let checkInTriggeredAt = Block.blockEndDate(for: lastFilledBlockIndex)
            let gracePeriod: TimeInterval = 20 * 60  // 20 minutes

            let timeSinceCheckIn = Date().timeIntervalSince(checkInTriggeredAt)

            if timeSinceCheckIn >= gracePeriod {
                // Grace period has passed - stop
                print("📱 Check-in grace period expired (\(Int(timeSinceCheckIn))s since check-in), stopping")
                handleStop()
            } else {
                // Still in grace period - send notification and show dialog
                let graceMinutesRemaining = Int((gracePeriod - timeSinceCheckIn) / 60)
                print("📱 Check-in limit reached, \(graceMinutesRemaining) min grace remaining")

                // Send immediate notification so user can respond without opening app
                NotificationManager.shared.scheduleCheckInNotification(
                    blockIndex: currentWallClockBlock,
                    graceMinutesRemaining: max(1, graceMinutesRemaining)
                )

                // Also set up the completion dialog state (shown if they open the app)
                // The dialog will show without auto-continue countdown because shouldSuppressAutoContinue is true
                timerManager.showTimerComplete = true
                timerManager.timerCompletedAt = checkInTriggeredAt

                // Update Live Activity to show the grace period countdown
                let graceEndAt = checkInTriggeredAt.addingTimeInterval(gracePeriod)
                WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                    autoContinueEndAt: graceEndAt,
                    isBreak: isBreak
                )
            }
        } else {
            // Under limit - start timer on current block
            timerManager.incrementInteractionCounter()
            handleContinueWork()
            print("📱 Started timer on block \(currentWallClockBlock) after \(blocksAutoFilled) retroactive fills")
        }
    }

    /// Mark a block as auto-filled with a full work/break segment
    private func markBlockAsAutoFilled(blockIndex: Int, category: String?, label: String?, isBreak: Bool) async {
        guard let block = blockManager.blocks.first(where: { $0.blockIndex == blockIndex }) else {
            print("⚠️ markBlockAsAutoFilled: Block \(blockIndex) not found")
            return
        }

        // Create a full-duration segment for this block
        let segment = BlockSegment(
            type: isBreak ? .break : .work,
            seconds: 1200,  // Full 20 minutes
            category: isBreak ? nil : category,
            label: isBreak ? nil : label,
            startElapsed: 0
        )

        var updatedBlock = block
        updatedBlock.status = .done
        updatedBlock.usedSeconds = 1200
        updatedBlock.progress = 100.0
        updatedBlock.visualFill = 1.0
        updatedBlock.segments = [segment]
        updatedBlock.category = category ?? block.category
        updatedBlock.label = label ?? block.label

        await blockManager.saveBlock(updatedBlock)
        blocksWithTimerUsage.insert(blockIndex)
    }

    private func handleSkipNextBlock() {
        // Skip the next block and continue to the one after
        // Use actual current time to determine which blocks to skip/continue
        let actualCurrentBlock = Block.getCurrentBlockIndex()
        let skipBlockIndex = actualCurrentBlock
        let continueBlockIndex = actualCurrentBlock + 1
        blocksWithTimerUsage.insert(continueBlockIndex)

        // Can't skip if we'd go past 72
        guard continueBlockIndex < 72 else {
            handleStop()
            return
        }

        let category = timerManager.currentCategory
        let label = timerManager.currentLabel

        // Mark the skipped block as skipped
        Task {
            if let skipBlock = blockManager.blocks.first(where: { $0.blockIndex == skipBlockIndex }) {
                var updatedBlock = skipBlock
                updatedBlock.status = .skipped
                await blockManager.saveBlock(updatedBlock)
            }
        }

        // Get existing segments from the block we're continuing to
        let continueBlock = blockManager.blocks.first { $0.blockIndex == continueBlockIndex }
        let existingSegments = continueBlock?.segments ?? []

        timerManager.continueToNextBlock(
            nextBlockIndex: continueBlockIndex,
            date: todayString,
            isBreakMode: false,
            category: category,
            label: label,
            existingSegments: existingSegments
        )

        // Activate and save the block - this handles unmuting and auto-skipping previous muted blocks
        Task {
            await blockManager.activateBlockForTimer(blockIndex: continueBlockIndex)
            await saveBlockForContinue(blockIndex: continueBlockIndex, category: category, label: label)
        }

        // Schedule notification at the continue block's end time
        NotificationManager.shared.scheduleTimerComplete(
            at: Block.blockEndDate(for: continueBlockIndex),
            blockIndex: continueBlockIndex,
            isBreak: false
        )

        // Trigger segment focus change (handles collapse/expand/scroll)
        NotificationCenter.default.post(name: .segmentFocusChanged, object: nil)
    }

    // MARK: - Planned Block Actions

    private func handleStartPlannedBlock(_ block: Block) {
        showPlannedBlockDialog = false
        plannedBlock = nil
        blocksWithTimerUsage.insert(block.blockIndex)

        // If this is a night block, activate it and auto-skip previous unused night blocks
        Task {
            await blockManager.activateBlockForTimer(blockIndex: block.blockIndex)
        }

        // Duration calculated automatically based on block boundary
        // Pass existing segments and visual fill so timer continues from where it left off
        timerManager.startTimer(
            for: block.blockIndex,
            date: todayString,
            isBreakMode: false,
            category: block.category,
            label: block.label,
            existingSegments: block.segments,
            existingVisualFill: block.visualFill
        )

        // Start Live Activity
        startWidgetLiveActivity(
            blockIndex: block.blockIndex,
            isBreak: false,
            endAt: Block.blockEndDate(for: block.blockIndex),
            category: block.category,
            label: block.label
        )

        // Schedule notification at actual block end time
        NotificationManager.shared.scheduleTimerComplete(
            at: Block.blockEndDate(for: block.blockIndex),
            blockIndex: block.blockIndex,
            isBreak: false
        )
    }

    private func handleStartPlannedBlockAsBreak(_ block: Block) {
        showPlannedBlockDialog = false
        plannedBlock = nil
        blocksWithTimerUsage.insert(block.blockIndex)

        // Start a break instead of the planned work (timer runs to block boundary)
        timerManager.startTimer(
            for: block.blockIndex,
            date: todayString,
            isBreakMode: true,
            category: nil,
            label: "Break",
            existingSegments: block.segments,
            existingVisualFill: block.visualFill
        )

        // Start Live Activity — break timer runs to block boundary
        startWidgetLiveActivity(
            blockIndex: block.blockIndex,
            isBreak: true,
            endAt: Block.blockEndDate(for: block.blockIndex),
            category: nil,
            label: "Break"
        )

        // Schedule notification for break reminder (5 minutes, not block end)
        NotificationManager.shared.scheduleTimerComplete(
            at: Date().addingTimeInterval(300),
            blockIndex: block.blockIndex,
            isBreak: true
        )
    }

    private func handleSkipPlannedBlock(_ block: Block) {
        showPlannedBlockDialog = false
        plannedBlock = nil
        dismissedPlannedBlocks.insert(block.blockIndex)

        Task {
            var updatedBlock = block
            updatedBlock.status = .skipped
            await blockManager.saveBlock(updatedBlock)
            await blockManager.reloadBlocks()
        }
    }

    private func handleDismissPlannedBlock(_ block: Block) {
        showPlannedBlockDialog = false
        plannedBlock = nil
        dismissedPlannedBlocks.insert(block.blockIndex)
    }

    // MARK: - Block Change Detection

    private func checkForBlockChange() {
        let newBlockIndex = currentBlockIndex

        // Day-end check: if past dayStartHour, user is idle, and block boundary crossed → show dialog
        if !isToday && !timerManager.isActive && !timerManager.showTimerComplete && !timerManager.showBreakComplete
            && !showDayEndDialog && !continuedPastDayEnd && newBlockIndex != lastCheckedBlockIndex {
            showDayEndDialog = true
        }

        guard isToday || continuedPastDayEnd else { return }

        // Check if we've moved to a new block
        if newBlockIndex != lastCheckedBlockIndex {
            lastCheckedBlockIndex = newBlockIndex

            // Run auto-skip for past blocks (only for today's data)
            if isToday {
                Task {
                    await blockManager.processAutoSkip(currentBlockIndex: newBlockIndex, timerBlockIndex: timerManager.currentBlockIndex, blocksWithTimerUsage: blocksWithTimerUsage)
                }
            }

            // Check if current block is planned
            // Only show planned dialog if:
            // 1. Block status is explicitly .planned
            // 2. Block has category or label (something was planned)
            // 3. We haven't already dismissed this dialog
            // 4. No timer is running
            // 5. Block doesn't already have work data (segments/progress) - this prevents showing for auto-continued blocks
            if let block = blockManager.blocks.first(where: { $0.blockIndex == newBlockIndex }),
               block.status == .planned,
               (block.category != nil || block.label != nil),
               !dismissedPlannedBlocks.contains(newBlockIndex),
               !timerManager.isActive,
               block.segments.isEmpty,
               block.progress == 0 {
                plannedBlock = block
                showPlannedBlockDialog = true
            }
        }
    }

    // MARK: - Pending Day Start Hour Change

    /// Check if a pending dayStartHour change should be applied
    /// This is called every 10 seconds by the periodic timer
    private func checkPendingDayStartHourChange() {
        // No pending change
        guard pendingDayStartHour >= 0, !pendingDayStartDateString.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()

        // Validate the pending date format and get current date string
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: pendingDayStartDateString) != nil else { return }

        let currentDateString = formatter.string(from: now)
        let currentHour = calendar.component(.hour, from: now)

        // Check if we've reached or passed the pending date and hour
        // The change takes effect when: current date >= pending date AND current hour >= pending hour
        if currentDateString >= pendingDayStartDateString && currentHour >= pendingDayStartHour {
            print("📅 Applying pending dayStartHour change: \(dayStartHour) → \(pendingDayStartHour)")

            // Apply the change
            dayStartHour = pendingDayStartHour

            // Clear the pending values
            pendingDayStartHour = -1
            pendingDayStartDateString = ""

            // Run auto-skip to process any past blocks after dayStartHour change
            Task {
                if isToday {
                    await blockManager.processAutoSkip(
                        currentBlockIndex: currentBlockIndex,
                        timerBlockIndex: timerManager.currentBlockIndex,
                        blocksWithTimerUsage: blocksWithTimerUsage
                    )
                }
            }

            // The change in dayStartHour will cause logicalToday to recalculate
            // which will cause isToday to potentially change
            // which will trigger DayEndDialog or auto-switch as appropriate
            // via the existing checkForBlockChange() logic
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
        .environmentObject(BlockManager())
        .environmentObject(TimerManager())
        .environmentObject(GoalManager())
}
