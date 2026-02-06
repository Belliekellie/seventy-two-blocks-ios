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

    private var currentBlockIndex: Int {
        Block.getCurrentBlockIndex()
    }

    @AppStorage("dayStartHour") private var dayStartHour = 6
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

    /// Count of completed (done) blocks today, excluding muted blocks
    private var completedBlocks: Int {
        blockManager.blocks.filter { $0.status == .done && !$0.isMuted }.count
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

                        // Quick Actions - only for today (these affect today's blocks)
                        if isToday {
                            QuickActionsView()
                                .padding(.horizontal, 4)
                        }

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
                    onCheckIn: { timerManager.resetInteractionCounter() },
                    onContinue: {
                        timerManager.resetInteractionCounter()
                        handleContinueWork()
                    },
                    onAutoContinue: {
                        timerManager.incrementInteractionCounter()
                        handleContinueWork()
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
            if newValue && showPlannedBlockDialog {
                showPlannedBlockDialog = false
                plannedBlock = nil
            }
        }
        .onChange(of: timerManager.showBreakComplete) { _, newValue in
            if newValue && showPlannedBlockDialog {
                showPlannedBlockDialog = false
                plannedBlock = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedBlockIndex != nil },
            set: { if !$0 { selectedBlockIndex = nil } }
        )) {
            if let blockIndex = selectedBlockIndex {
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = "yyyy-MM-dd"
                BlockSheetView(blockIndex: blockIndex, date: formatter.string(from: selectedDate))
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
        }
        .sheet(isPresented: $showOverview) {
            OverviewSheetView()
        }
        .onAppear {
            // Initialize selectedDate to logical today (accounting for dayStartHour)
            selectedDate = logicalToday
        }
        .task {
            async let blocksLoad: Void = blockManager.loadBlocks(for: selectedDate)
            async let goalsLoad: Void = goalManager.loadGoals(for: selectedDate)
            _ = await (blocksLoad, goalsLoad)
            setupTimerCallbacks()
            _ = await NotificationManager.shared.requestPermission()
            NotificationManager.shared.setupNotificationCategories()

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
                NotificationManager.shared.pendingAction = nil
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
            } else {
                // 6b. No notification action — user just opened the app.
                //     If they've been away a while (> 30s), show a FRESH dialog
                //     so they can consciously choose what to do.
                //     Don't auto-fill blocks — they might not have been working.
                if timerManager.showTimerComplete, let completedAt = timerManager.timerCompletedAt {
                    let elapsed = Date().timeIntervalSince(completedAt)
                    if shouldSuppressAutoContinue {
                        // Check-in mode — don't reset timerCompletedAt.
                        // The dialog's 20-min grace period countdown uses the original
                        // completion time and will handle auto-stop if it expires.
                        // But update Live Activity to show grace period instead of stale auto-continue
                        let graceEndAt = completedAt.addingTimeInterval(1200)
                        WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                            autoContinueEndAt: graceEndAt,
                            isBreak: false
                        )
                    } else if elapsed > 30 {
                        // Reset to now so the dialog shows a fresh 25s countdown
                        timerManager.timerCompletedAt = Date()
                        // Update Live Activity with fresh auto-continue countdown
                        let newAutoContinueEndAt = Date().addingTimeInterval(25)
                        WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                            autoContinueEndAt: newAutoContinueEndAt,
                            isBreak: false
                        )
                    }
                    // If <= 30s, the dialog's existing countdown handles it naturally
                } else if timerManager.showBreakComplete, let completedAt = timerManager.timerCompletedAt {
                    let elapsed = Date().timeIntervalSince(completedAt)
                    if elapsed > 35 {
                        timerManager.timerCompletedAt = Date()
                        // Update Live Activity with fresh auto-continue countdown
                        let newAutoContinueEndAt = Date().addingTimeInterval(30)
                        WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                            autoContinueEndAt: newAutoContinueEndAt,
                            isBreak: true
                        )
                    }
                }
            }

            // 7. Reload blocks, goals, and auto-skip
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
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            checkForBlockChange()
        }
    }

    // MARK: - Timer Callbacks

    private func setupTimerCallbacks() {
        timerManager.onTimerComplete = { blockIndex, date, isBreak, secondsUsed, initialTime, segments in
            // Track this block as having timer usage
            self.blocksWithTimerUsage.insert(blockIndex)

            // IMMEDIATELY update local state (synchronous, no race condition)
            // This ensures the grid shows correct state before the async DB save finishes
            // Status = .done means "block was worked on" (shows time breakdown UI)
            // Fill is determined by segments, not status (so partial fills display correctly)
            let actualProgress = min(100.0, Double(secondsUsed) / 1200.0 * 100.0)
            if let idx = self.blockManager.blocks.firstIndex(where: { $0.blockIndex == blockIndex }) {
                self.blockManager.blocks[idx].status = .done
                self.blockManager.blocks[idx].segments = segments
                self.blockManager.blocks[idx].usedSeconds = secondsUsed
                self.blockManager.blocks[idx].progress = actualProgress
                print("✅ Marked block \(blockIndex) as .done, progress: \(Int(actualProgress))%")
            }
            Task {
                await self.saveTimerCompletion(blockIndex: blockIndex, date: date, secondsUsed: secondsUsed, initialTime: initialTime, segments: segments)
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
            } else if timerManager.showTimerComplete || timerManager.showBreakComplete {
                // Timer completed - update Live Activity to show auto-continue countdown
                let autoContinueSeconds: TimeInterval = timerManager.showBreakComplete ? 30 : 25
                if let completedAt = timerManager.timerCompletedAt {
                    let autoContinueEndAt = completedAt.addingTimeInterval(autoContinueSeconds)
                    WidgetDataProvider.shared.updateLiveActivityForAutoContinue(
                        autoContinueEndAt: autoContinueEndAt,
                        isBreak: timerManager.showBreakComplete
                    )
                }
            }
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
    }

    private func saveTimerCompletion(blockIndex: Int, date: String, secondsUsed: Int, initialTime: Int, segments: [BlockSegment]) async {
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

        // Always mark as done - user worked on this block, so it's "complete"
        // The fill is determined by segments (can be partial), not by status
        updatedBlock.status = .done
        updatedBlock.category = timerManager.currentCategory ?? block.category
        updatedBlock.label = timerManager.currentLabel ?? block.label

        // Use the segments passed from the callback (captured before clearing)
        updatedBlock.segments = segments

        print("💾 saveTimerCompletion: block \(blockIndex), used \(secondsUsed)s, progress \(Int(actualProgress))%, segments: \(segments.count)")

        await blockManager.saveBlock(updatedBlock)
        await blockManager.reloadBlocks()
    }

    private func saveSnapshot(blockIndex: Int, date: String, snapshot: Run) async {
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
        // During break, don't overwrite the block's category/label with the
        // timer's stale work values — the block should keep whatever was set
        // when work was active. Only update during work mode.
        if !timerManager.isBreak {
            updatedBlock.category = timerManager.currentCategory ?? block.category
            updatedBlock.label = timerManager.currentLabel ?? block.label
        }
        // Also save the combined segments so they persist on refresh
        updatedBlock.segments = allSegments

        await blockManager.saveBlock(updatedBlock)
        print("💾 Saved snapshot for block \(blockIndex) - usedSeconds: \(totalUsedSeconds), progress: \(Int(newProgress))%")
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
            // IMPORTANT: Unmute and activate the block if it was muted (e.g., night/sleep blocks)
            // This allows work to continue into deactivated sections
            if block.isMuted {
                print("🌙 Activating muted block \(blockIndex) for continuation")
                updatedBlock.isMuted = false
                updatedBlock.isActivated = true
            }
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
        WidgetDataProvider.shared.startLiveActivity(
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

    // MARK: - Dialog Actions

    private func handleContinueWork() {
        // ALWAYS continue on the CURRENT TIME block
        // The timer completed at the block boundary, so the current block IS the next one
        // If the user waited before clicking, we still go to wherever "now" is
        // NEVER start a timer on a future block
        let actualCurrentBlock = Block.getCurrentBlockIndex()
        let nextBlockIndex = actualCurrentBlock
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
        let nextBlock = blockManager.blocks.first { $0.blockIndex == nextBlockIndex }
        let existingSegments = nextBlock?.segments ?? []

        timerManager.continueToNextBlock(
            nextBlockIndex: nextBlockIndex,
            date: todayString,
            isBreakMode: wasBreak,
            category: category,
            label: label,
            existingSegments: existingSegments
        )

        // Start Live Activity
        startWidgetLiveActivity(
            blockIndex: nextBlockIndex,
            isBreak: wasBreak,
            endAt: Block.blockEndDate(for: nextBlockIndex),
            category: category,
            label: label
        )

        // Activate and save the block - this handles unmuting and auto-skipping previous muted blocks
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
        let nextBlock = blockManager.blocks.first { $0.blockIndex == nextBlockIndex }
        let existingSegments = nextBlock?.segments ?? []

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
        // Stop the timer if still running (e.g., mid-block break notification)
        if timerManager.isActive {
            timerManager.stopTimer(markComplete: false)
        }
        timerManager.dismissTimerComplete()
        timerManager.dismissBreakComplete()
        NotificationManager.shared.cancelAllNotifications()
        WidgetDataProvider.shared.endLiveActivity()
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
        // Pass existing segments so timer continues from where it left off
        timerManager.startTimer(
            for: block.blockIndex,
            date: todayString,
            isBreakMode: false,
            category: block.category,
            label: block.label,
            existingSegments: block.segments
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
            existingSegments: block.segments
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
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
        .environmentObject(BlockManager())
        .environmentObject(TimerManager())
        .environmentObject(GoalManager())
}
