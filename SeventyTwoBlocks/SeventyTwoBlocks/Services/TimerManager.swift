import Foundation
import Combine

private let MIN_SEGMENT_SECONDS = 10

@MainActor
final class TimerManager: ObservableObject {
    // MARK: - Published State
    @Published var isActive = false
    @Published var isPaused = false  // Explicit paused state for UI
    @Published var isBreak = false
    @Published var timeLeft: Int = 1200  // 20 minutes in seconds
    @Published var initialTime: Int = 1200
    @Published var currentBlockIndex: Int?
    @Published var currentDate: String?
    @Published var progress: Double = 0
    @Published var breakProgress: Double = 0

    // Block data
    @Published var currentCategory: String?
    @Published var currentLabel: String?

    // Pre-break work context (preserved when taking a break, restored when going back to work)
    @Published var lastWorkCategory: String?
    @Published var lastWorkLabel: String?

    // Completion state
    @Published var showTimerComplete = false
    @Published var showBreakComplete = false
    @Published var showPausedExpiry = false  // Block time ended while paused
    @Published var timerCompletedAt: Date?
    @Published var isBackgroundCompletion = false  // True if timer completed while app was backgrounded

    // Check-in tracking: counts consecutive auto-continues without user interaction
    @Published var blocksSinceLastInteraction: Int = 0

    // MARK: - Internal State
    private var startedAt: Date?
    private var endAt: Date?
    private var activeRunId: String?
    private var timer: Timer?
    private var autosaveTimer: Timer?
    private var pausedExpiryTimer: Timer?  // Fires when block time ends while paused
    private var secondsUsedAtPause: Int = 0  // Preserves fill position when paused

    // Segments tracking (exposed for UI rendering)
    // previousSegments: segments from previous timer sessions on this block (already saved)
    // liveSegments: segments created during this current timer session
    @Published private(set) var previousSegments: [BlockSegment] = []
    @Published private(set) var liveSegments: [BlockSegment] = []
    @Published private(set) var currentSegmentStartElapsed: Int = 0
    @Published private(set) var currentSegmentType: BlockSegment.SegmentType = .work

    // Scale factor: maps real seconds to visual proportion (0..1)
    // When there are previous segments, this accounts for remaining visual space
    @Published private(set) var sessionScaleFactor: Double = 1.0 / 1200.0

    // Visual proportion already used by previous segments (0..1)
    // Exposed for UI rendering - previous segments use this as their total width
    @Published private(set) var previousVisualProportion: Double = 0

    // Break tracking
    private var breakStartTime: Date?
    private var totalBreakSeconds: Int = 0
    private var breakNotifyAt: Date?  // When to fire the 5-min break popup (timer keeps running)

    // Callbacks
    // onTimerComplete: blockIndex, date, isBreak, secondsUsed, initialTime, segments (finalized), visualFill (0..1)
    // initialTime is passed so caller can detect natural completion (secondsUsed ~= initialTime)
    // visualFill is the actual visual fill proportion reached during timer sessions
    var onTimerComplete: ((Int, String, Bool, Int, Int, [BlockSegment], Double) -> Void)?
    var onSaveSnapshot: ((Int, String, Run) -> Void)?  // blockIndex, date, snapshot
    var onWidgetUpdate: (() -> Void)?

    // Widget update throttling: only notify at 25% progress milestones
    private var lastReportedProgressQuarter: Int = -1

    // MARK: - Computed Properties

    /// Read-only access to endAt for widget countdown
    var exposedEndAt: Date? { endAt }
    var exposedStartedAt: Date? { startedAt }

    var secondsUsed: Int {
        return max(0, initialTime - timeLeft)
    }

    var formattedTimeLeft: String {
        let minutes = timeLeft / 60
        let seconds = timeLeft % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progressPercent: Double {
        guard initialTime > 0 else { return 0 }
        return Double(secondsUsed) / Double(initialTime) * 100
    }

    /// Current visual fill proportion (0..1) - where the color bar has actually reached
    /// This accounts for previous segments + live segments + current in-progress segment
    /// Used for saving to block.visualFill so render shows actual fill, not forced 100%
    var currentVisualFill: Double {
        // Start with previous segments' visual proportion
        var fill = previousVisualProportion

        // Add live segments using the session scale factor
        let liveSegs = liveSegmentsIncludingCurrent
        for seg in liveSegs {
            fill += Double(seg.seconds) * sessionScaleFactor
        }

        return min(fill, 1.0)
    }

    /// All segments including previous segments and the current in-progress "tail" segment
    /// This is what the UI should use to render the fill
    var allSegmentsIncludingCurrent: [BlockSegment] {
        // Start with previous segments (from earlier timer sessions)
        var segments = previousSegments
        // Add live segments from current session
        segments.append(contentsOf: liveSegments)
        // Add current in-progress segment
        let elapsed = secondsUsed
        let currentDuration = elapsed - currentSegmentStartElapsed
        if currentDuration > 0 {
            segments.append(BlockSegment(
                type: currentSegmentType,
                seconds: currentDuration,
                category: currentSegmentType == .work ? currentCategory : nil,
                label: currentSegmentType == .work ? currentLabel : nil,
                startElapsed: currentSegmentStartElapsed
            ))
        }
        return segments
    }

    /// Live segments only (current session) including in-progress segment
    /// Used by UI to render with sessionScaleFactor (separate from previousSegments)
    var liveSegmentsIncludingCurrent: [BlockSegment] {
        var segments = liveSegments
        let elapsed = secondsUsed
        let currentDuration = elapsed - currentSegmentStartElapsed
        if currentDuration > 0 {
            segments.append(BlockSegment(
                type: currentSegmentType,
                seconds: currentDuration,
                category: currentSegmentType == .work ? currentCategory : nil,
                label: currentSegmentType == .work ? currentLabel : nil,
                startElapsed: currentSegmentStartElapsed
            ))
        }
        return segments
    }

    // MARK: - Interaction Counter

    func resetInteractionCounter() {
        blocksSinceLastInteraction = 0
    }

    func incrementInteractionCounter() {
        blocksSinceLastInteraction += 1
    }

    // MARK: - Timer Control

    func startTimer(for blockIndex: Int, date: String, isBreakMode: Bool = false, category: String? = nil, label: String? = nil, existingSegments: [BlockSegment] = [], existingVisualFill: Double? = nil) {
        // GUARD: Never start a timer on a past or future block
        let currentTimeBlock = Block.getCurrentBlockIndex()
        if blockIndex < currentTimeBlock {
            print("⏱️ Block \(blockIndex) is in the past (current: \(currentTimeBlock)), cannot start timer")
            return
        }
        if blockIndex > currentTimeBlock {
            print("⏱️ Block \(blockIndex) is in the future (current: \(currentTimeBlock)), cannot start timer")
            return
        }

        // Stop any existing timer
        stopTimerInternal()

        // Calculate actual duration based on block boundaries (for work mode)
        let actualDuration: Int
        let actualEndAt: Date
        let preciseInterval: Double  // Exact time interval for accurate scale factor

        // Both break and work modes use block boundary endAt
        // Breaks use a separate breakNotifyAt for the 5-min popup
        actualEndAt = Block.blockEndDate(for: blockIndex)
        preciseInterval = actualEndAt.timeIntervalSinceNow

        if preciseInterval <= 0 {
            print("⏱️ Block \(blockIndex) has already passed, cannot start timer")
            return
        }
        // Round up so we don't show 0 seconds initially
        actualDuration = Int(ceil(preciseInterval))

        // Use saved visual fill if provided, otherwise calculate from segments
        // This preserves the actual visual position from previous sessions
        if let savedFill = existingVisualFill, savedFill > 0 {
            previousVisualProportion = min(savedFill, 1.0)
            print("⏱️ Using saved visual fill: \(String(format: "%.1f%%", previousVisualProportion * 100))")
        } else {
            // Fallback: calculate from segments using 1/1200 scale
            let blockDuration = 1200.0
            let existingVisualProportion = existingSegments.reduce(0.0) { sum, seg in
                sum + Double(seg.seconds) / blockDuration
            }
            previousVisualProportion = min(existingVisualProportion, 1.0)
            let totalSegmentSeconds = existingSegments.reduce(0) { $0 + $1.seconds }
            print("⏱️ Calculated visual fill from \(existingSegments.count) segments (\(totalSegmentSeconds)s): \(String(format: "%.1f%%", previousVisualProportion * 100))")
        }

        // Calculate remaining visual space
        let remainingVisualProportion = max(0, 1.0 - previousVisualProportion)

        if remainingVisualProportion <= 0 && !isBreakMode {
            print("⏱️ Block \(blockIndex) has no visual space left (100% filled), cannot start timer")
            return
        }

        // Set up new timer state
        currentBlockIndex = blockIndex
        currentDate = date
        initialTime = actualDuration
        timeLeft = actualDuration
        isActive = true
        isBreak = isBreakMode
        currentCategory = category
        currentLabel = label
        activeRunId = UUID().uuidString

        // Initialize/preserve work context
        if !isBreakMode {
            // Starting in work mode - this is the work context to preserve
            lastWorkCategory = category
            lastWorkLabel = label
        } else if lastWorkCategory == nil {
            // Starting directly in break mode with no prior work context —
            // seed from the passed category/label so "Back to Work" has
            // something to restore
            lastWorkCategory = category
            lastWorkLabel = label
        }
        // When starting in break mode with existing lastWork* values,
        // we keep them so we can restore them when going back to work

        // Epoch-based timing for crash tolerance
        startedAt = Date()
        endAt = actualEndAt

        // Store previous segments (from earlier sessions) for rendering
        previousSegments = existingSegments

        // Initialize new live segments for this session
        liveSegments = []
        currentSegmentStartElapsed = 0
        currentSegmentType = isBreakMode ? .break : .work
        totalBreakSeconds = 0

        // Calculate scale factor based on remaining visual proportion
        // This ensures the new segments fill the remaining visual space
        // scaleFactor = remainingVisualProportion / remainingRealTime
        // Both break and work use the same formula (breaks fill toward block boundary)
        sessionScaleFactor = preciseInterval > 0 ? remainingVisualProportion / preciseInterval : 1.0 / 1200.0

        if isBreakMode {
            breakStartTime = Date()
            breakNotifyAt = Date().addingTimeInterval(300)  // 5-min popup trigger
        }

        // Start tick timer
        startTickTimer()

        // Start autosave timer (every 5 seconds)
        startAutosaveTimer()

        // Notify widget of timer start
        lastReportedProgressQuarter = -1
        onWidgetUpdate?()

        print("⏱️ Timer started for block \(blockIndex) - initialTime: \(actualDuration)s, preciseInterval: \(String(format: "%.3f", preciseInterval))s, isBreak: \(isBreakMode), existingSegments: \(existingSegments.count), previousProportion: \(String(format: "%.1f%%", previousVisualProportion * 100)), sessionScaleFactor: \(String(format: "%.8f", sessionScaleFactor))")
    }

    func stopTimer(markComplete: Bool = false) {
        // Allow stopping when active OR paused
        guard isActive || isPaused else { return }

        // Finalize current segment (only if was active, not if paused)
        if isActive {
            finalizeCurrentSegment()
        }

        // CRITICAL: Capture all data BEFORE clearing state
        let blockIndex = currentBlockIndex
        let date = currentDate
        let wasBreak = isBreak
        let used = secondsUsed

        // Combine previous segments with live segments for final result
        // This preserves work from earlier timer sessions
        let finalSegments = previousSegments + liveSegments

        // Capture initialTime before clearing
        let sessionInitialTime = initialTime

        // Capture visual fill BEFORE clearing state
        let capturedVisualFill = currentVisualFill

        let totalSegmentSeconds = finalSegments.reduce(0) { $0 + $1.seconds }
        print("⏱️ Timer stopped - used=\(used)s, previousSegs=\(previousSegments.count) (\(previousSegments.reduce(0) { $0 + $1.seconds })s), liveSegs=\(liveSegments.count) (\(liveSegments.reduce(0) { $0 + $1.seconds })s), totalSegmentSeconds=\(totalSegmentSeconds)s, visualFill=\(String(format: "%.1f%%", capturedVisualFill * 100))")

        // Stop tick timers immediately (but don't clear @Published state yet)
        timer?.invalidate()
        timer = nil
        autosaveTimer?.invalidate()
        autosaveTimer = nil

        // Save segments FIRST - callback updates local blocks array synchronously
        if let blockIndex = blockIndex, let date = date, !finalSegments.isEmpty {
            onTimerComplete?(blockIndex, date, wasBreak, used, sessionInitialTime, finalSegments, capturedVisualFill)
        }

        // NOW clear @Published state - blocks array is already updated
        // This triggers SwiftUI re-render, but blocks have correct data
        stopTimerInternal()

        // Notify widget of timer stop
        onWidgetUpdate?()
    }

    func pauseTimer() {
        guard isActive else { return }

        // Invalidate timers first (synchronous, immediate)
        timer?.invalidate()
        timer = nil
        autosaveTimer?.invalidate()
        autosaveTimer = nil

        // Use current secondsUsed (based on displayed timeLeft, not recalculated)
        // This prevents the 1-second shave when pausing mid-tick
        let pauseSecondsUsed = secondsUsed

        // Finalize segment data
        let segmentDuration = pauseSecondsUsed - currentSegmentStartElapsed
        if segmentDuration > 0 {
            let segment = BlockSegment(
                type: currentSegmentType,
                seconds: segmentDuration,
                category: currentSegmentType == .work ? currentCategory : nil,
                label: currentSegmentType == .work ? currentLabel : nil,
                startElapsed: currentSegmentStartElapsed
            )
            liveSegments.append(segment)
        }

        // Store pause position
        secondsUsedAtPause = pauseSecondsUsed
        currentSegmentStartElapsed = pauseSecondsUsed

        // Update state - timeLeft stays as-is (what user saw on screen)
        isActive = false
        isPaused = true

        // Schedule a timer to show paused expiry dialog when block time ends
        if let blockIndex = currentBlockIndex {
            let blockEnd = Block.blockEndDate(for: blockIndex)
            let timeUntilBlockEnd = blockEnd.timeIntervalSinceNow
            if timeUntilBlockEnd > 0 {
                pausedExpiryTimer?.invalidate()
                pausedExpiryTimer = Timer.scheduledTimer(withTimeInterval: timeUntilBlockEnd, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        self?.handlePausedExpiry()
                    }
                }
            }
        }

        print("⏱️ Timer paused at \(timeLeft)s remaining, secondsUsed=\(secondsUsedAtPause)")
    }

    func resumeTimer() {
        guard isPaused, let blockIndex = currentBlockIndex else { return }

        // Cancel the paused expiry timer since we're resuming
        pausedExpiryTimer?.invalidate()
        pausedExpiryTimer = nil

        // Check if block time has already elapsed while paused
        let blockEnd = Block.blockEndDate(for: blockIndex)
        if blockEnd <= Date() {
            // Block time has passed while paused - show special dialog
            // User didn't work during the pause, so don't give credit for that time
            print("⏱️ Block time elapsed while paused - showing paused expiry dialog")

            // Keep the timer in a stopped state but show the paused expiry dialog
            isPaused = false
            showPausedExpiry = true
            timerCompletedAt = Date()  // For dialog timestamp
            return
        }

        // Calculate real time left based on block boundary
        let realTimeLeft = max(0, Int(blockEnd.timeIntervalSinceNow))
        let preciseInterval = blockEnd.timeIntervalSinceNow
        timeLeft = realTimeLeft
        endAt = blockEnd

        // Adjust initialTime so secondsUsed stays where it was at pause
        // secondsUsed = initialTime - timeLeft
        // We want secondsUsed = secondsUsedAtPause
        // So: initialTime = secondsUsedAtPause + timeLeft
        initialTime = secondsUsedAtPause + timeLeft

        // CRITICAL: Capture the actual visual fill achieved at pause time BEFORE moving segments
        // This is where the color bar actually is - we must preserve this exactly
        let visualFillAtPause = currentVisualFill

        // Move live segments to previous segments
        previousSegments = previousSegments + liveSegments
        liveSegments = []

        // Set previousVisualProportion to the ACTUAL visual fill, not recalculated from seconds
        // This ensures live segments start exactly where the color bar was at pause
        previousVisualProportion = visualFillAtPause

        // Calculate new scale factor for remaining work
        // This ensures fill reaches 100% exactly when timer ends
        let remainingVisualProportion = max(0, 1.0 - visualFillAtPause)
        sessionScaleFactor = preciseInterval > 0 ? remainingVisualProportion / preciseInterval : 1.0 / 1200.0

        // Start a fresh segment from current position
        currentSegmentStartElapsed = secondsUsed

        isActive = true
        isPaused = false

        startTickTimer()
        startAutosaveTimer()

        print("⏱️ Timer resumed: timeLeft=\(timeLeft)s, initialTime=\(initialTime), secondsUsed=\(secondsUsed), visualFillAtPause=\(String(format: "%.1f%%", visualFillAtPause * 100)), newScaleFactor=\(String(format: "%.8f", sessionScaleFactor))")
    }

    // MARK: - Work/Break Switching

    func switchToBreak() {
        guard isActive, !isBreak else { return }

        // Preserve work context before switching to break
        lastWorkCategory = currentCategory
        lastWorkLabel = currentLabel

        // Split segment (captures current work category/label into the segment)
        splitSegment(toType: .break)

        // Keep currentCategory/currentLabel as-is so the block cell continues
        // to display the work label in normal color while on break.
        // The autosave skips writing category/label during break mode.

        isBreak = true
        breakStartTime = Date()
        breakNotifyAt = Date().addingTimeInterval(300)  // 5-min popup trigger

        // Save snapshot immediately after mode switch (crash recovery)
        saveSnapshot()

        // Defer widget update to let SwiftUI settle first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.onWidgetUpdate?()
        }
        print("⏱️ Switched to break mode, preserved work context: \(lastWorkCategory ?? "nil") / \(lastWorkLabel ?? "nil")")
    }

    func switchToWork() {
        guard isActive, isBreak else { return }

        // Calculate break time
        if let breakStart = breakStartTime {
            totalBreakSeconds += Int(Date().timeIntervalSince(breakStart))
        }

        // Restore work context from before the break
        currentCategory = lastWorkCategory
        currentLabel = lastWorkLabel

        // Split segment - creates the break segment before switching type
        splitSegment(toType: .work)

        isBreak = false
        breakStartTime = nil
        breakNotifyAt = nil  // Cancel any pending break notification

        // Save snapshot immediately after mode switch (crash recovery)
        // This ensures the break segment is persisted before any UI updates
        saveSnapshot()

        // Defer widget update to let SwiftUI settle first
        // This prevents UI freeze from too many rapid state changes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.onWidgetUpdate?()
        }
        print("⏱️ Switched to work mode, restored work context: \(currentCategory ?? "nil") / \(currentLabel ?? "nil")")
    }

    // MARK: - Break Notification (mid-block popup, timer keeps running)

    /// Called when 5 minutes of break have elapsed. Shows the break dialog
    /// but does NOT stop the timer — the block continues toward its boundary.
    private func handleBreakNotification() {
        guard isBreak, !showBreakComplete else { return }
        breakNotifyAt = nil  // Fire once
        showBreakComplete = true
        timerCompletedAt = Date()  // For auto-continue countdown in dialog
        onWidgetUpdate?()
        print("⏱️ Break notification fired (5 min elapsed) — timer still running")
    }

    /// Dismiss the mid-block break notification without stopping the timer.
    /// Does NOT clear timerCompletedAt — that's owned by handleTimerComplete()
    /// and clearing it here races with the block-boundary completion dialog.
    func dismissBreakNotification() {
        showBreakComplete = false
    }

    /// Snooze the break notification — dismiss dialog and schedule another in `duration` seconds
    func snoozeBreakNotification(duration: Int = 300) {
        breakNotifyAt = Date().addingTimeInterval(TimeInterval(duration))
        dismissBreakNotification()
        print("⏱️ Break notification snoozed for \(duration)s")
    }

    /// Update category/label while timer is running
    /// Creates a segment boundary if category OR label changes (with 10s minimum for label-only)
    func updateCategory(_ newCategory: String?, label newLabel: String?) {
        guard isActive else { return }

        let categoryChanged = newCategory != currentCategory
        let labelChanged = newLabel != currentLabel

        // Create segment boundary if category OR label changed (not during break)
        if (categoryChanged || labelChanged) && !isBreak {
            let elapsed = secondsUsed
            let segmentDuration = elapsed - currentSegmentStartElapsed

            // For label-only changes, require minimum duration to prevent micro-segments
            let isLabelOnlyChange = labelChanged && !categoryChanged
            let shouldCreateBoundary = segmentDuration > 0 &&
                (!isLabelOnlyChange || segmentDuration >= MIN_SEGMENT_SECONDS)

            if shouldCreateBoundary {
                let segment = BlockSegment(
                    type: .work,
                    seconds: segmentDuration,
                    category: currentCategory,
                    label: currentLabel,
                    startElapsed: currentSegmentStartElapsed
                )
                liveSegments.append(segment)
                currentSegmentStartElapsed = elapsed
            }
        }

        // Always update current values
        currentCategory = newCategory
        currentLabel = newLabel

        // During break, also update the saved work context so switchToWork()
        // picks up the user's new choice instead of restoring the old one
        if isBreak {
            lastWorkCategory = newCategory
            lastWorkLabel = newLabel
        }

        onWidgetUpdate?()
        print("⏱️ Updated category: \(newCategory ?? "nil"), label: \(newLabel ?? "nil")")
    }

    // MARK: - Private Methods

    private func stopTimerInternal() {
        timer?.invalidate()
        timer = nil
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        pausedExpiryTimer?.invalidate()
        pausedExpiryTimer = nil

        isActive = false
        isPaused = false
        timeLeft = 0
        progress = 0
        breakProgress = 0
        secondsUsedAtPause = 0
        currentBlockIndex = nil
        currentDate = nil
        startedAt = nil
        endAt = nil
        activeRunId = nil
        breakStartTime = nil
        breakNotifyAt = nil
        previousSegments = []
        liveSegments = []
        currentSegmentStartElapsed = 0
        currentSegmentType = .work
        sessionScaleFactor = 1.0 / 1200.0
        previousVisualProportion = 0
        lastReportedProgressQuarter = -1
        // NOTE: Do NOT reset blocksSinceLastInteraction here.
        // stopTimerInternal() is called by startTimer() during auto-continue,
        // which would wipe the counter and defeat the check-in system.
        // The counter is reset explicitly by resetInteractionCounter() on user actions,
        // and in resetState() when the user stops/dismisses.
    }

    private func startTickTimer() {
        timer?.invalidate()
        // Schedule on main run loop for immediate UI updates
        timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func startAutosaveTimer() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.saveSnapshot()
            }
        }
        RunLoop.main.add(autosaveTimer!, forMode: .common)
    }

    private func tick() {
        guard isActive, let endAt = endAt else { return }

        let remaining = Int(endAt.timeIntervalSinceNow)
        timeLeft = max(0, remaining)

        // Update progress
        if initialTime > 0 {
            progress = Double(secondsUsed) / Double(initialTime) * 100
        }

        // Check if break notification should fire (5-min popup, timer keeps running)
        if isBreak, let notifyAt = breakNotifyAt, Date() >= notifyAt {
            handleBreakNotification()
        }

        // Throttled widget update at 25% progress milestones
        if initialTime > 0 {
            let progressQuarter = Int(progress / 25)
            if progressQuarter != lastReportedProgressQuarter {
                lastReportedProgressQuarter = progressQuarter
                onWidgetUpdate?()
            }
        }

        // Debug: Show fill proportion when close to end
        let fillProportion = Double(secondsUsed) * sessionScaleFactor + previousVisualProportion
        if fillProportion > 0.95 {
            print("⏱️ DEBUG: timeLeft=\(timeLeft), secondsUsed=\(secondsUsed), fillProportion=\(String(format: "%.4f", fillProportion)), sessionScaleFactor=\(String(format: "%.8f", sessionScaleFactor))")
        }

        // Check for completion
        if timeLeft <= 0 {
            handleTimerComplete()
        }
    }

    private func handleTimerComplete() {
        print("⏱️ handleTimerComplete called - isActive: \(isActive)")
        // Capture actual end time BEFORE state changes
        // If timer expired while backgrounded, endAt is in the past (when it actually expired)
        let actualCompletionTime = endAt ?? Date()
        guard isActive else {
            print("⏱️ handleTimerComplete SKIPPED - isActive was false!")
            return
        }

        // Finalize segment
        finalizeCurrentSegment()

        // CRITICAL: Capture all data BEFORE clearing state
        let blockIndex = currentBlockIndex
        let date = currentDate
        let wasBreak = isBreak
        // Combine previous segments with live segments for final result
        // This preserves work from earlier timer sessions (matches stopTimer behavior)
        let finalSegments = previousSegments + liveSegments

        // Stop the timer but keep state for dialog
        timer?.invalidate()
        timer = nil
        autosaveTimer?.invalidate()
        autosaveTimer = nil
        isActive = false
        timeLeft = 0

        // Ensure secondsUsed equals initialTime at completion
        progress = 100

        // For natural completion (timer hit 0), visual fill should be 1.0 (100%)
        // This is because the scale factor is calculated so fill reaches 100% at block boundary
        // Even if you start with 1 minute left, completing that minute = 100% of YOUR work session
        let completionVisualFill = 1.0

        // Notify completion with captured segments
        // For natural completion, secondsUsed == initialTime (timer reached 0)
        if let blockIndex = blockIndex, let date = date {
            onTimerComplete?(blockIndex, date, wasBreak, initialTime, initialTime, finalSegments, completionVisualFill)
        }

        // Always show timer complete dialog at block boundary (block time is up)
        // Dismiss any mid-block break notification if one was showing
        showBreakComplete = false
        breakNotifyAt = nil
        showTimerComplete = true
        print("⏱️ DEBUG: showTimerComplete set to TRUE, isActive=\(isActive)")

        // Record completion time for epoch-based auto-continue countdown
        // Uses actual end time, not current time, so backgrounded duration is accounted for
        timerCompletedAt = actualCompletionTime

        // Detect if this was a background completion (timer expired while app was suspended)
        // If more than 5 seconds have passed since actual completion, user wasn't watching
        let timeSinceCompletion = Date().timeIntervalSince(actualCompletionTime)
        isBackgroundCompletion = timeSinceCompletion > 5
        if isBackgroundCompletion {
            print("⏱️ Background completion detected: \(Int(timeSinceCompletion))s since block ended")
        }

        // Notify widget of timer completion
        onWidgetUpdate?()

        print("⏱️ Timer complete! Was break: \(wasBreak), segments: \(finalSegments.count) (previous: \(previousSegments.count), live: \(liveSegments.count))")
    }

    private func splitSegment(toType newType: BlockSegment.SegmentType) {
        let elapsed = secondsUsed
        let segmentDuration = elapsed - currentSegmentStartElapsed

        if segmentDuration > 0 {
            let segment = BlockSegment(
                type: currentSegmentType,
                seconds: segmentDuration,
                category: currentSegmentType == .work ? currentCategory : nil,
                label: currentSegmentType == .work ? currentLabel : nil,
                startElapsed: currentSegmentStartElapsed
            )
            liveSegments.append(segment)
        }

        currentSegmentStartElapsed = elapsed
        currentSegmentType = newType
    }

    private func finalizeCurrentSegment() {
        let elapsed = secondsUsed
        let segmentDuration = elapsed - currentSegmentStartElapsed

        print("⏱️ finalizeCurrentSegment: elapsed=\(elapsed)s, currentSegmentStartElapsed=\(currentSegmentStartElapsed), segmentDuration=\(segmentDuration)s, initialTime=\(initialTime), timeLeft=\(timeLeft)")

        if segmentDuration > 0 {
            let segment = BlockSegment(
                type: currentSegmentType,
                seconds: segmentDuration,
                category: currentSegmentType == .work ? currentCategory : nil,
                label: currentSegmentType == .work ? currentLabel : nil,
                startElapsed: currentSegmentStartElapsed
            )
            liveSegments.append(segment)
            print("⏱️ Created segment: \(segmentDuration)s \(currentSegmentType), liveSegments now has \(liveSegments.count) segments totaling \(liveSegments.reduce(0) { $0 + $1.seconds })s")
            // Update start position so liveSegmentsIncludingCurrent doesn't double-count
            currentSegmentStartElapsed = elapsed
        } else {
            print("⏱️ No segment created (duration <= 0)")
        }
    }

    private func saveSnapshot() {
        guard let blockIndex = currentBlockIndex,
              let date = currentDate,
              let runId = activeRunId,
              let startedAt = startedAt else { return }

        // Create current segment for snapshot
        var snapshotSegments = liveSegments
        let elapsed = secondsUsed
        let currentSegmentDuration = elapsed - currentSegmentStartElapsed
        if currentSegmentDuration > 0 {
            snapshotSegments.append(BlockSegment(
                type: currentSegmentType,
                seconds: currentSegmentDuration,
                category: currentSegmentType == .work ? currentCategory : nil,
                label: currentSegmentType == .work ? currentLabel : nil,
                startElapsed: currentSegmentStartElapsed
            ))
        }

        let snapshot = Run(
            id: runId,
            startedAt: startedAt.timeIntervalSince1970,
            endedAt: nil,
            initialRealTime: Double(initialTime),
            scaleFactor: 1.0,
            segments: snapshotSegments,
            currentSegmentStart: Double(currentSegmentStartElapsed),
            currentType: currentSegmentType,
            currentCategory: currentCategory,
            lastWorkCategory: lastWorkCategory  // Use actual lastWorkCategory, not currentCategory
        )

        onSaveSnapshot?(blockIndex, date, snapshot)
    }

    // MARK: - Background Recovery

    /// Called when app returns to foreground. If the timer expired while backgrounded,
    /// triggers completion. Otherwise recalculates timeLeft and restarts tick timers.
    func restoreFromBackground() {
        print("🔄 restoreFromBackground: isActive=\(isActive), endAt=\(endAt?.description ?? "nil")")
        guard isActive, let endAt = endAt else {
            print("🔄 restoreFromBackground: skipping (not active or no endAt)")
            return
        }

        if endAt <= Date() {
            // Timer expired while app was suspended
            // CRITICAL: Update timeLeft to 0 so secondsUsed = initialTime
            // This ensures the full work time is recorded, not just the time
            // the app was active before backgrounding
            print("🔄 restoreFromBackground: timer expired, completing")
            timeLeft = 0
            handleTimerComplete()
        } else {
            // Timer still running — recalculate and restart timers
            timeLeft = max(0, Int(endAt.timeIntervalSinceNow))
            if initialTime > 0 {
                progress = Double(secondsUsed) / Double(initialTime) * 100
            }
            print("🔄 restoreFromBackground: timer still running, timeLeft=\(timeLeft)s")
            startTickTimer()
            startAutosaveTimer()

            // Check if break notification should have fired while backgrounded
            if let notifyAt = breakNotifyAt, notifyAt <= Date() {
                handleBreakNotification()
            }
        }
    }

    /// Called when app enters background. Persists current timer state to DB.
    func saveStateForBackground() {
        guard isActive else { return }
        saveSnapshot()
    }

    // MARK: - Dialog Actions

    func dismissTimerComplete() {
        showTimerComplete = false
        timerCompletedAt = nil
        resetState()
    }

    func dismissBreakComplete() {
        showBreakComplete = false
        timerCompletedAt = nil
        resetState()
    }

    /// Save partial block data without resetting state - used when continuing to next block
    func savePartialBlockData() {
        if let blockIndex = currentBlockIndex, let date = currentDate {
            let finalSegments = previousSegments + liveSegments
            // Calculate visual fill based on paused position
            let partialVisualFill = currentVisualFill
            // Don't mark complete - just save the partial progress
            onTimerComplete?(blockIndex, date, isBreak, secondsUsedAtPause, initialTime, finalSegments, partialVisualFill)
        }
    }

    /// Called when block time ends while timer is paused
    private func handlePausedExpiry() {
        guard isPaused else { return }

        print("⏱️ Block time ended while paused - showing paused expiry dialog")

        pausedExpiryTimer?.invalidate()
        pausedExpiryTimer = nil
        isPaused = false
        showPausedExpiry = true
        timerCompletedAt = Date()
    }

    /// Dismiss paused expiry dialog and fully reset - used when stopping
    func dismissPausedExpiry() {
        showPausedExpiry = false
        timerCompletedAt = nil
        savePartialBlockData()
        resetState()
    }

    private func resetState() {
        currentBlockIndex = nil
        currentDate = nil
        currentCategory = nil
        currentLabel = nil
        lastWorkCategory = nil
        lastWorkLabel = nil
        activeRunId = nil
        liveSegments = []
        currentSegmentStartElapsed = 0
        currentSegmentType = .work
        sessionScaleFactor = 1.0 / 1200.0
        progress = 0
        breakProgress = 0
        breakNotifyAt = nil
        lastReportedProgressQuarter = -1
        blocksSinceLastInteraction = 0
        isPaused = false
    }

    // MARK: - Continue Actions

    func continueToNextBlock(nextBlockIndex: Int, date: String, isBreakMode: Bool = false, category: String? = nil, label: String? = nil, existingSegments: [BlockSegment] = []) {
        showTimerComplete = false
        showBreakComplete = false
        showPausedExpiry = false
        // Duration is calculated automatically based on block boundaries for work mode
        // Pass existing segments so we continue from where the block left off (if any)
        startTimer(for: nextBlockIndex, date: date, isBreakMode: isBreakMode, category: category, label: label, existingSegments: existingSegments)
    }
}
