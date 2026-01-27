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

    private var currentBlockIndex: Int {
        Block.getCurrentBlockIndex()
    }

    @AppStorage("dayStartHour") private var dayStartHour = 6

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

    /// Count of completed (done) blocks today, excluding muted blocks
    private var completedBlocks: Int {
        blockManager.blocks.filter { $0.status == .done && !$0.isMuted }.count
    }

    var body: some View {
        ZStack {
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
                        // Stats Card (Worked + Overview)
                        // Extra padding to align with block colors
                        StatsCardView(showOverview: $showOverview)
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

                        // Small spacer for visual breathing room above sticky bottom
                        Spacer().frame(height: 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }

                // STICKY BOTTOM SECTION - Timer (when active) + Bottom Bar
                // Connected together with no gap
                VStack(spacing: 0) {
                    if timerManager.isActive {
                        FloatingTimerBar()
                    }
                    StickyBottomBar()
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
                    onContinue: handleContinueWork,
                    onTakeBreak: handleTakeBreak,
                    onStartNewBlock: handleStartNewBlock,
                    onSkipNextBlock: handleSkipNextBlock,
                    onStop: handleStop
                )
                .transition(.scale.combined(with: .opacity))
            }

            if timerManager.showBreakComplete {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }

                BreakCompleteDialog(
                    blockIndex: timerManager.currentBlockIndex ?? 0,
                    onContinueBreak: handleExtendBreak,
                    onBackToWork: handleBackToWork,
                    onStartNewBlock: handleStartNewBlock,
                    onStop: handleStop
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
        }
        .animation(.easeInOut(duration: 0.2), value: timerManager.showTimerComplete)
        .animation(.easeInOut(duration: 0.2), value: timerManager.showBreakComplete)
        .animation(.easeInOut(duration: 0.2), value: showPlannedBlockDialog)
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
                    await blockManager.processAutoSkip(currentBlockIndex: currentBlockIndex, timerBlockIndex: timerManager.currentBlockIndex)
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
            await blockManager.loadBlocks(for: selectedDate)
            await goalManager.loadGoals(for: selectedDate)
            setupTimerCallbacks()
            _ = await NotificationManager.shared.requestPermission()
            NotificationManager.shared.setupNotificationCategories()

            // Run auto-skip on initial load for today
            if isToday {
                await blockManager.processAutoSkip(currentBlockIndex: currentBlockIndex, timerBlockIndex: timerManager.currentBlockIndex)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Run auto-skip when app comes to foreground
            if isToday {
                Task {
                    await blockManager.reloadBlocks()
                    await blockManager.processAutoSkip(currentBlockIndex: currentBlockIndex, timerBlockIndex: timerManager.currentBlockIndex)
                }
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            Task {
                await blockManager.loadBlocks(for: newDate)
                await goalManager.loadGoals(for: newDate)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            // Check for block changes every minute
            checkForBlockChange()
        }
    }

    // MARK: - Timer Callbacks

    private func setupTimerCallbacks() {
        timerManager.onTimerComplete = { blockIndex, date, isBreak, secondsUsed, initialTime, segments in
            Task {
                await self.saveTimerCompletion(blockIndex: blockIndex, date: date, secondsUsed: secondsUsed, initialTime: initialTime, segments: segments)
            }
        }

        timerManager.onSaveSnapshot = { blockIndex, date, snapshot in
            Task {
                await saveSnapshot(blockIndex: blockIndex, date: date, snapshot: snapshot)
            }
        }
    }

    private func saveTimerCompletion(blockIndex: Int, date: String, secondsUsed: Int, initialTime: Int, segments: [BlockSegment]) async {
        guard let block = blockManager.blocks.first(where: { $0.blockIndex == blockIndex }) else { return }

        // Calculate progress based on actual time used vs block duration
        let blockDurationSeconds = 20 * 60  // 1200 seconds
        let actualProgress = min(100.0, Double(secondsUsed) / Double(blockDurationSeconds) * 100.0)

        // Determine if this was a natural completion (timer reached block boundary)
        // Natural completion: secondsUsed ~= initialTime (within 5 second tolerance for timing jitter)
        let isNaturalCompletion = secondsUsed >= initialTime - 5

        var updatedBlock = block
        updatedBlock.usedSeconds = secondsUsed
        updatedBlock.progress = actualProgress

        // Mark as done if:
        // 1. Natural completion (timer reached block boundary), OR
        // 2. Completed >= 95% of a full 20-minute block
        // This ensures blocks started late but completed to boundary are marked done
        updatedBlock.status = (isNaturalCompletion || actualProgress >= 95) ? .done : block.status
        updatedBlock.category = timerManager.currentCategory ?? block.category
        updatedBlock.label = timerManager.currentLabel ?? block.label

        // Use the segments passed from the callback (captured before clearing)
        updatedBlock.segments = segments

        print("💾 saveTimerCompletion: block \(blockIndex), used \(secondsUsed)s, initialTime \(initialTime)s, progress \(Int(actualProgress))%, natural: \(isNaturalCompletion), segments: \(segments.count)")

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
        updatedBlock.category = timerManager.currentCategory ?? block.category
        updatedBlock.label = timerManager.currentLabel ?? block.label
        // Also save the combined segments so they persist on refresh
        updatedBlock.segments = allSegments

        await blockManager.saveBlock(updatedBlock)
        print("💾 Saved snapshot for block \(blockIndex) - usedSeconds: \(totalUsedSeconds), progress: \(Int(newProgress))%")
    }

    private func saveBlockForContinue(blockIndex: Int, category: String?, label: String?) async {
        print("🔄 saveBlockForContinue: block \(blockIndex), category: \(category ?? "nil"), label: \(label ?? "nil")")

        // Find or create the block for the continued work
        if let block = blockManager.blocks.first(where: { $0.blockIndex == blockIndex }) {
            print("🔄 Found existing block, updating...")
            var updatedBlock = block
            updatedBlock.category = category
            updatedBlock.label = label
            updatedBlock.status = .planned  // Mark as active/planned
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
                status: .planned,
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
        await blockManager.reloadBlocks()
        print("🔄 Blocks reloaded")
    }

    // MARK: - Dialog Actions

    private func handleContinueWork() {
        // ALWAYS continue on the CURRENT TIME block
        // The timer completed at the block boundary, so the current block IS the next one
        // If the user waited before clicking, we still go to wherever "now" is
        // NEVER start a timer on a future block
        let actualCurrentBlock = Block.getCurrentBlockIndex()
        let nextBlockIndex = actualCurrentBlock

        guard nextBlockIndex < 72 else {
            handleStop()
            return
        }

        let category = timerManager.currentCategory
        let label = timerManager.currentLabel

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

        // Activate and save the block - this handles unmuting and auto-skipping previous muted blocks
        Task {
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

    private func handleTakeBreak() {
        // Always use the actual current time block for break
        let blockIndex = Block.getCurrentBlockIndex()

        timerManager.continueToNextBlock(
            nextBlockIndex: blockIndex,
            date: todayString,
            isBreakMode: true,
            category: nil,
            label: "Break"
        )

        // Schedule notification for break (5 minutes)
        NotificationManager.shared.scheduleTimerComplete(
            at: Date().addingTimeInterval(300),
            blockIndex: blockIndex,
            isBreak: true
        )
    }

    private func handleStartNewBlock() {
        timerManager.dismissTimerComplete()
        // Open block selection sheet for current block
        selectedBlockIndex = currentBlockIndex
    }

    private func handleExtendBreak() {
        // ALWAYS extend break on the CURRENT TIME block
        let actualCurrentBlock = Block.getCurrentBlockIndex()
        let timerBlockIndex = timerManager.currentBlockIndex ?? currentBlockIndex
        let blockIndex = actualCurrentBlock

        guard blockIndex < 72 else {
            handleStop()
            return
        }

        // Get segments: from timer if same block, from saved data if moving to new block
        let timerSegments = timerManager.previousSegments + timerManager.liveSegments

        let existingSegments: [BlockSegment]
        if blockIndex != timerBlockIndex {
            // Moving to new block - get that block's existing segments (if any)
            let targetBlock = blockManager.blocks.first { $0.blockIndex == blockIndex }
            existingSegments = targetBlock?.segments ?? []
        } else {
            // Staying on same block - continue with timer's segments
            existingSegments = timerSegments
        }

        timerManager.extendBreak(blockIndex: blockIndex, date: todayString, duration: 300, existingSegments: existingSegments)

        // Activate the block if it's muted (for extending break into night blocks)
        Task {
            await blockManager.activateBlockForTimer(blockIndex: blockIndex)
        }

        // Schedule notification for extended break (5 minutes)
        NotificationManager.shared.scheduleTimerComplete(
            at: Date().addingTimeInterval(300),
            blockIndex: blockIndex,
            isBreak: true
        )
    }

    private func handleBackToWork() {
        // ALWAYS resume work on the CURRENT TIME block
        // Never jump to a future block - that makes no sense
        // The break was happening on some block, but "back to work" means
        // "start working now" which is always the current time block
        let actualCurrentBlock = Block.getCurrentBlockIndex()

        guard actualCurrentBlock < 72 else {
            handleStop()
            return
        }

        let nextBlockIndex = actualCurrentBlock

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

        // Activate and save the block - this handles unmuting and auto-skipping previous muted blocks
        Task {
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
        timerManager.dismissTimerComplete()
        timerManager.dismissBreakComplete()
        NotificationManager.shared.cancelAllNotifications()
    }

    private func handleSkipNextBlock() {
        // Skip the next block and continue to the one after
        // Use actual current time to determine which blocks to skip/continue
        let actualCurrentBlock = Block.getCurrentBlockIndex()
        let skipBlockIndex = actualCurrentBlock
        let continueBlockIndex = actualCurrentBlock + 1

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

        // Start a break instead of the planned work
        timerManager.startTimer(
            for: block.blockIndex,
            date: todayString,
            isBreakMode: true,
            category: nil,
            label: "Break",
            existingSegments: block.segments
        )

        // Schedule notification for break (5 minutes)
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
        guard isToday else { return }

        let newBlockIndex = currentBlockIndex

        // Check if we've moved to a new block
        if newBlockIndex != lastCheckedBlockIndex {
            lastCheckedBlockIndex = newBlockIndex

            // Run auto-skip for past blocks
            Task {
                await blockManager.processAutoSkip(currentBlockIndex: newBlockIndex, timerBlockIndex: timerManager.currentBlockIndex)
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
