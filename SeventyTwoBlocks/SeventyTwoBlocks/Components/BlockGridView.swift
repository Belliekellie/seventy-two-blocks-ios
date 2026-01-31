import SwiftUI
import Combine

// MARK: - Notifications
extension Notification.Name {
    static let segmentFocusChanged = Notification.Name("segmentFocusChanged")
}

// MARK: - Motivational Insults (matching web app)
let SKIPPED_INSULTS = [
    "PATHETIC!", "USELESS!", "LAZY!", "TERRIBLE!", "SHAMEFUL!",
    "WASTED!", "WEAK!", "FAILURE!", "TRAGIC!", "HOPELESS!",
    "PROCRASTINATOR!", "TIMEWASTER!", "DAYDREAMER!", "SLACKER!", "DISAPPOINTING!",
    "PITIFUL!", "WORTHLESS!", "DISGRACEFUL!", "EMBARRASSING!", "UNPRODUCTIVE!",
    "IDLE!", "NEGLECTED!", "ABANDONED!", "FORGOTTEN!", "SQUANDERED!",
    "FUMBLED!", "BOTCHED!", "BUNGLED!", "MEDIOCRE!", "AMATEUR!"
]

/// Get a deterministic insult for a block (stable across re-renders)
func getSkippedInsult(blockIndex: Int) -> String {
    return SKIPPED_INSULTS[blockIndex % SKIPPED_INSULTS.count]
}

// MARK: - Segment Definition
struct DaySegment: Identifiable {
    let id: String
    var label: String
    let icon: String
    let startBlock: Int
    let endBlock: Int
    let displayOffset: Int // For day-order block numbering

    static func segments(morning: String = "Morning", afternoon: String = "Afternoon & Evening", night: String = "Night") -> [DaySegment] {
        return [
            DaySegment(id: "morning", label: morning, icon: "sun.max.fill", startBlock: 24, endBlock: 47, displayOffset: -23),
            DaySegment(id: "afternoon", label: afternoon, icon: "sun.haze.fill", startBlock: 48, endBlock: 71, displayOffset: -23),
            DaySegment(id: "sleep", label: night, icon: "moon.fill", startBlock: 0, endBlock: 23, displayOffset: 49)
        ]
    }

    static let defaultSegments = segments()

    /// Get display block number (1-72 in day order)
    func displayBlockNumber(_ blockIndex: Int) -> Int {
        return blockIndex + displayOffset
    }

    /// Check if block index is in this segment
    func contains(_ blockIndex: Int) -> Bool {
        return blockIndex >= startBlock && blockIndex <= endBlock
    }
}

// MARK: - Block Grid View
struct BlockGridView: View {
    let blocks: [Block]
    let date: Date
    @Binding var selectedBlockIndex: Int?

    // Settings
    @AppStorage("segmentNameMorning") private var segmentNameMorning = "Morning"
    @AppStorage("segmentNameAfternoon") private var segmentNameAfternoon = "Afternoon & Evening"
    @AppStorage("segmentNameNight") private var segmentNameNight = "Night"
    @AppStorage("showMotivationalInsults") private var showMotivationalInsults = false

    // Collapse state management
    @State private var collapsedSegments: [String: Bool] = [:]
    @State private var pinnedOpen: Set<String> = []      // User manually opened after auto-expand
    @State private var pinnedClosed: Set<String> = []    // User manually closed after auto-expand
    @State private var surfaced: Set<String> = []        // Segments that have been auto-expanded
    @State private var didInitialize = false
    @State private var lastSegmentId: String = ""
    @State private var shouldScrollToCurrentBlock = true

    // 3 columns for the grid (3 blocks = 1 hour)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private var segments: [DaySegment] {
        DaySegment.segments(morning: segmentNameMorning, afternoon: segmentNameAfternoon, night: segmentNameNight)
    }

    private var currentBlockIndex: Int {
        Block.getCurrentBlockIndex()
    }

    private var currentSegmentId: String {
        for segment in segments {
            if segment.contains(currentBlockIndex) {
                return segment.id
            }
        }
        return "morning"
    }

    @AppStorage("dayStartHour") private var dayStartHour = 6

    /// Whether the displayed date matches the "logical today" (accounting for dayStartHour)
    private var isToday: Bool {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // If current hour is before dayStartHour, we're still in the previous logical day
        let logicalDate: Date
        if currentHour < dayStartHour {
            logicalDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        } else {
            logicalDate = now
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: logicalDate)
        return dateString == todayString
    }

    // Persistence key for this date
    private var persistenceKey: String {
        "collapsedSegments:\(dateString)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                ForEach(segments) { segment in
                    SegmentSection(
                        segment: segment,
                        blocks: blocksForSegment(segment),
                        dateString: dateString,
                        isCollapsed: isSegmentCollapsed(segment.id),
                        showMotivationalInsults: showMotivationalInsults,
                        isViewingToday: isToday,
                        onToggle: { toggleSegment(segment.id) },
                        selectedBlockIndex: $selectedBlockIndex
                    )
                    .id("segment-\(segment.id)")
                }
            }
            .onAppear {
                initializeCollapseState()

                // Scroll to current block after a short delay
                if shouldScrollToCurrentBlock && isToday {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("block-\(currentBlockIndex)", anchor: UnitPoint(x: 0.5, y: 0.35))
                        }
                        shouldScrollToCurrentBlock = false
                    }
                }
            }
            .onChange(of: date) { _, _ in
                // Reset state when date changes
                didInitialize = false
                shouldScrollToCurrentBlock = true
                pinnedOpen.removeAll()
                pinnedClosed.removeAll()
                surfaced.removeAll()
                initializeCollapseState()

                // Scroll to current block for today
                if isToday {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("block-\(currentBlockIndex)", anchor: UnitPoint(x: 0.5, y: 0.35))
                        }
                    }
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                // Check for segment change every minute (only for today)
                if isToday {
                    handleSegmentChange(proxy: proxy)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .segmentFocusChanged)) { notification in
                // Triggered when timer actions cause segment change (continue, start new block, etc.)
                if isToday {
                    handleSegmentChange(proxy: proxy)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // When returning from background, immediately check if segment changed
                // (e.g., user left app at night, opens in morning)
                if isToday {
                    handleSegmentChange(proxy: proxy)
                }
            }
        }
    }

    // MARK: - Collapse State Management

    private func initializeCollapseState() {
        guard !didInitialize else { return }
        didInitialize = true

        // Try to load persisted state for today
        if isToday, let savedData = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([String: Bool].self, from: savedData) {
            var state = saved

            // IMPORTANT: Always ensure the current segment is open on load
            // This fixes the case where saved state has a stale segment open (e.g., night)
            // but the user opens the app in a different segment (e.g., morning)
            let activeSegment = currentSegmentId
            if state[activeSegment] == true {
                // Current segment was collapsed in saved state - open it
                state[activeSegment] = false

                // Collapse all other segments that aren't pinned open by user
                for segment in segments where segment.id != activeSegment {
                    if !pinnedOpen.contains(segment.id) {
                        state[segment.id] = true
                    }
                }
            }

            collapsedSegments = state
            lastSegmentId = activeSegment
            surfaced.insert(activeSegment)
            saveCollapseState()
            return
        }

        // Default: only current segment open (for today), or all open (for other days)
        var initial: [String: Bool] = [:]
        for segment in segments {
            if isToday {
                initial[segment.id] = segment.id != currentSegmentId
            } else {
                initial[segment.id] = false // All open for past/future days
            }
        }
        collapsedSegments = initial
        lastSegmentId = currentSegmentId
        surfaced.insert(currentSegmentId)

        saveCollapseState()
    }

    private func isSegmentCollapsed(_ segmentId: String) -> Bool {
        return collapsedSegments[segmentId] ?? (segmentId != currentSegmentId)
    }

    private func toggleSegment(_ segmentId: String) {
        let wasCollapsed = isSegmentCollapsed(segmentId)

        withAnimation(.easeInOut(duration: 0.2)) {
            collapsedSegments[segmentId] = !wasCollapsed
        }

        // Track user intent for auto-collapse logic
        if surfaced.contains(segmentId) {
            if wasCollapsed {
                // User opened a previously surfaced segment - pin it open
                pinnedOpen.insert(segmentId)
                pinnedClosed.remove(segmentId)
            } else {
                // User closed a surfaced segment - pin it closed
                pinnedClosed.insert(segmentId)
                pinnedOpen.remove(segmentId)
            }
        }

        saveCollapseState()
    }

    private func saveCollapseState() {
        guard isToday else { return }
        if let data = try? JSONEncoder().encode(collapsedSegments) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func handleSegmentChange(proxy: ScrollViewProxy) {
        let newSegmentId = currentSegmentId

        guard newSegmentId != lastSegmentId else { return }

        let oldSegmentId = lastSegmentId
        lastSegmentId = newSegmentId

        // TIME TRUMPS PINS - clear pinnedOpen on old segment when time naturally changes
        // This matches web app behavior: "Time changes always clear pinned state"
        pinnedOpen.remove(oldSegmentId)

        // Auto-collapse old segment (now that pinnedOpen is cleared, it will collapse)
        withAnimation(.easeInOut(duration: 0.2)) {
            collapsedSegments[oldSegmentId] = true
        }

        // Auto-expand new segment (unless user explicitly closed it via pinnedClosed)
        // But current segment always wins - if time moved here, it should open
        if !pinnedClosed.contains(newSegmentId) {
            withAnimation(.easeInOut(duration: 0.2)) {
                collapsedSegments[newSegmentId] = false
            }
            surfaced.insert(newSegmentId)

            // Scroll to current block
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("block-\(currentBlockIndex)", anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
        }

        saveCollapseState()
    }

    private func blocksForSegment(_ segment: DaySegment) -> [Block] {
        let segmentBlocks = blocks.filter { $0.blockIndex >= segment.startBlock && $0.blockIndex <= segment.endBlock }
        return segmentBlocks.sorted { $0.blockIndex < $1.blockIndex }
    }
}

// MARK: - Segment Section
struct SegmentSection: View {
    let segment: DaySegment
    let blocks: [Block]
    let dateString: String
    let isCollapsed: Bool
    let showMotivationalInsults: Bool
    let isViewingToday: Bool
    let onToggle: () -> Void
    @Binding var selectedBlockIndex: Int?

    // 3 columns for the grid (3 blocks = 1 hour)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var blockRange: String {
        let start = segment.displayBlockNumber(segment.startBlock)
        let end = segment.displayBlockNumber(segment.endBlock)
        return "\(start)-\(end)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segment header - extra padding to align with cards above
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: segment.icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(segment.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("(Block \(segment.id == "morning" ? "1" : segment.id == "afternoon" ? "2" : "3"))")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.6))

                    Spacer()

                    Text(blockRange)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.5))

                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            // Block grid (collapsible)
            if !isCollapsed {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(segment.startBlock...segment.endBlock, id: \.self) { blockIndex in
                        let block = blocks.first { $0.blockIndex == blockIndex }
                        BlockItemView(
                            block: block,
                            blockIndex: blockIndex,
                            segment: segment,
                            showMotivationalInsults: showMotivationalInsults,
                            isViewingToday: isViewingToday
                        )
                        .id("block-\(blockIndex)")
                        .onTapGesture {
                            // Just set the block index - BlockSheetView will look up the current block
                            if let existingBlock = block {
                                print("👆 Tapped block \(blockIndex): id='\(existingBlock.id)', label='\(existingBlock.label ?? "nil")'")
                            } else {
                                print("👆 Tapped block \(blockIndex): no existing block in local state")
                            }
                            selectedBlockIndex = blockIndex
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Block Item View
struct BlockItemView: View {
    let block: Block?
    let blockIndex: Int
    let segment: DaySegment
    let showMotivationalInsults: Bool
    let isViewingToday: Bool
    @EnvironmentObject var blockManager: BlockManager
    @EnvironmentObject var timerManager: TimerManager
    @Environment(\.colorScheme) var colorScheme

    private var displayNumber: Int {
        segment.displayBlockNumber(blockIndex)
    }

    private var timeString: String {
        Block.blockToTime(blockIndex)
    }

    /// Is this the current block RIGHT NOW? Only true if viewing today
    private var isCurrentBlock: Bool {
        isViewingToday && blockIndex == Block.getCurrentBlockIndex()
    }

    /// Timer is actively running on this block - only possible on today's blocks
    private var isTimerActiveOnThisBlock: Bool {
        isViewingToday && timerManager.isActive && timerManager.currentBlockIndex == blockIndex
    }

    /// Past block - either viewing a past day (all blocks are past) or viewing today with earlier block
    private var isPastBlock: Bool {
        if !isViewingToday {
            // When viewing past days, all blocks are "past"
            // When viewing future days, none are past
            return false  // We'll handle this differently - future days get isFutureBlock
        }
        return blockIndex < Block.getCurrentBlockIndex()
    }

    /// Future block - either viewing a future day (all blocks are future) or viewing today with later block
    private var isFutureBlock: Bool {
        if !isViewingToday {
            // When not viewing today, all blocks are effectively "future" (can't start timer)
            return true
        }
        return blockIndex > Block.getCurrentBlockIndex()
    }

    private var isDone: Bool {
        block?.status == .done
    }

    private var isSkipped: Bool {
        block?.status == .skipped
    }

    private var isPlanned: Bool {
        block?.status == .planned && isFutureBlock
    }

    private var isMuted: Bool {
        block?.isMuted ?? false
    }

    private var categoryColor: Color? {
        guard let categoryId = block?.category,
              let category = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return nil
        }
        return category.swiftUIColor
    }

    private var categoryLabel: String? {
        guard let categoryId = block?.category,
              let category = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return nil
        }
        return category.label
    }

    private var backgroundColor: Color {
        if isMuted && block?.isActivated != true {
            return Color.gray.opacity(0.15)
        }

        if isDone {
            if let color = categoryColor {
                return color
            }
            return .green.opacity(0.8)
        }

        if isSkipped {
            // Skipped blocks with recorded data should show their category color
            if hasSegments, let color = categoryColor {
                return color
            }
            return Color.gray.opacity(0.1)
        }

        if isPlanned {
            if let color = categoryColor {
                return color.opacity(0.15)
            }
            return Color.gray.opacity(0.1)
        }

        return Color.gray.opacity(0.08)
    }

    private var borderColor: Color {
        // Timer active block gets highlighted border
        if isTimerActiveOnThisBlock {
            return timerManager.isBreak ? .red : (timerCategoryColor ?? categoryColor ?? .green)
        }

        // Done blocks get a subtle border matching their category
        if isDone, let catColor = categoryColor {
            return catColor.opacity(0.8)
        }

        if isCurrentBlock {
            return categoryColor ?? .primary
        }

        if isPlanned, let color = categoryColor {
            return color
        }

        if isPastBlock {
            return Color.gray.opacity(0.3)
        }

        return Color.gray.opacity(0.2)
    }

    /// Get category color from timer (for when block data hasn't updated yet)
    private var timerCategoryColor: Color? {
        guard let categoryId = timerManager.currentCategory,
              let category = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return nil
        }
        return category.swiftUIColor
    }

    /// Get category label from timer (for when block data hasn't updated yet)
    private var timerCategoryLabel: String? {
        guard let categoryId = timerManager.currentCategory,
              let category = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return nil
        }
        return category.label
    }

    /// Get color for a segment based on its type and category
    private func colorForSegment(_ segment: BlockSegment) -> Color {
        if segment.type == .break {
            return .red
        }
        if let categoryId = segment.category,
           let category = blockManager.categories.first(where: { $0.id == categoryId }) {
            return category.swiftUIColor
        }
        // Fallback to current category color or green
        return categoryColor ?? timerCategoryColor ?? .green
    }

    /// Calculate the starting proportion (0..1) for a segment at a given index
    private func segmentStartProportion(at index: Int, segments: [BlockSegment], scaleFactor: Double) -> Double {
        var start: Double = 0
        for i in 0..<index {
            start += Double(segments[i].seconds) * scaleFactor
        }
        return min(start, 1.0)
    }

    private var borderWidth: CGFloat {
        if isTimerActiveOnThisBlock {
            return 3.0  // Thick border for active timer
        }
        if isDone {
            return 1.5  // Lit up border for completed blocks
        }
        if isCurrentBlock {
            return 2.5
        }
        if isPlanned {
            return 1.5
        }
        return 1
    }

    /// Check if block has segment data
    private var hasSegments: Bool {
        guard let segments = block?.segments else { return false }
        return !segments.isEmpty
    }

    /// Calculate total seconds from segments (matches web app exactly)
    private var totalSecondsFromSegments: Int {
        guard let segments = block?.segments else { return 0 }
        return segments.reduce(0) { $0 + $1.seconds }
    }

    /// Check if block has any break segments
    private var hasBreakSegments: Bool {
        guard let segments = block?.segments else { return false }
        return segments.contains { $0.type == .break && $0.seconds > 0 }
    }

    /// Minimum seconds for the first segment to count (filters spillover from previous block)
    private let spilloverThreshold = 60

    /// Count of distinct work activities (category+label pairs), applying spillover threshold only to first segment
    private var distinctMeaningfulActivityCount: Int {
        guard let segments = block?.segments else { return 0 }
        let workSegments = segments.filter { $0.type == .work && $0.seconds > 0 }
        guard !workSegments.isEmpty else { return 0 }

        var activityTime: [String: Int] = [:]
        for (index, seg) in workSegments.enumerated() {
            // Only apply minimum duration to first segment (spillover filter)
            if index == 0 && seg.seconds < spilloverThreshold {
                continue
            }
            let key = "\(seg.category ?? "_none_")|\(seg.label ?? "_none_")"
            activityTime[key, default: 0] += seg.seconds
        }
        return activityTime.filter { $0.value > 0 }.count
    }

    /// Get the dominant category (most time) from work segments
    private var dominantCategory: String? {
        guard let segments = block?.segments else { return nil }
        var categoryTime: [String: Int] = [:]
        for seg in segments where seg.type == .work && seg.seconds > 0 {
            let cat = seg.category ?? "_none_"
            categoryTime[cat, default: 0] += seg.seconds
        }
        let sorted = categoryTime.sorted { $0.value > $1.value }
        if let top = sorted.first, top.key != "_none_" {
            return top.key
        }
        return nil
    }

    /// Get dominant label from segments (one with most time)
    private var dominantLabelFromSegments: String? {
        guard let segments = block?.segments else { return nil }
        var labelTime: [String: Int] = [:]
        for seg in segments where seg.type == .work {
            let label = seg.label ?? ""
            labelTime[label, default: 0] += seg.seconds
        }
        // Find label with most time
        let sorted = labelTime.sorted { $0.value > $1.value }
        if let top = sorted.first, !top.key.isEmpty {
            return top.key
        }
        return nil
    }

    /// Check if block has any work segments with actual time
    private var hasWorkSegments: Bool {
        guard let segments = block?.segments else { return false }
        return segments.contains { $0.type == .work && $0.seconds > 0 }
    }

    /// Total break seconds from segments
    private var totalBreakSeconds: Int {
        guard let segments = block?.segments else { return 0 }
        return segments.filter { $0.type == .break }.reduce(0) { $0 + $1.seconds }
    }

    /// Total work seconds from segments
    private var totalWorkSeconds: Int {
        guard let segments = block?.segments else { return 0 }
        return segments.filter { $0.type == .work }.reduce(0) { $0 + $1.seconds }
    }

    /// Build display label for done blocks with +N suffix for additional categories
    /// The dominant activity (work or break by time) always wins the block label
    private var doneBlockDisplayLabel: String? {
        // If block has NO work segments, it's break-only — just show "Break"
        if !hasWorkSegments {
            if hasBreakSegments {
                return "Break"
            }
            return nil
        }

        // If break is the dominant activity (more time than work), show "Break"
        // with +N for work categories that had meaningful time
        if hasBreakSegments && totalBreakSeconds > totalWorkSeconds {
            let meaningfulWorkCategories = distinctMeaningfulActivityCount
            if meaningfulWorkCategories > 0 {
                return "Break +\(meaningfulWorkCategories)"
            }
            return "Break"
        }

        // Work is dominant - get the primary work label
        // Use dominant label from segments (most time), then block label, then category name
        let dominantLabel = dominantLabelFromSegments
        let blockLabel = block?.label?.isEmpty == false ? block?.label : nil

        // Don't use block label if it's "Break" (leftover from break mode)
        let safePrimaryLabel: String?
        if let bl = blockLabel, bl.lowercased() == "break" {
            safePrimaryLabel = dominantLabel ?? categoryLabel
        } else {
            safePrimaryLabel = blockLabel ?? dominantLabel ?? categoryLabel
        }

        guard var result = safePrimaryLabel, !result.isEmpty else {
            return nil
        }

        // Add +N suffix showing how many ADDITIONAL categories/types with meaningful time (60s+)
        // Brief spillover (<60s) from continuing into a block is ignored
        var extraCount = distinctMeaningfulActivityCount - 1
        // Count break as an extra category if present (any duration)
        if hasBreakSegments {
            extraCount += 1
        }
        if extraCount > 0 {
            result += " +\(extraCount)"
        }

        return result
    }

    /// Calculate display minutes from segments (preferred) or usedSeconds (fallback)
    /// Matches web app logic: rounds up to 20m if worked 19+ minutes (95% of block)
    /// Returns nil if no time should be displayed
    private func calculateDisplayMinutes() -> Int? {
        // Skipped blocks should not show time (even if they have legacy data)
        if isSkipped {
            return nil
        }

        // Prefer segment data, fall back to usedSeconds
        var totalSeconds = totalSecondsFromSegments
        if totalSeconds == 0 {
            totalSeconds = block?.usedSeconds ?? 0
        }

        // No time to display
        if totalSeconds == 0 {
            return nil
        }

        // Round up to full block (20m) if worked 19+ minutes (95%)
        // This credits auto-continue and quick starts without penalizing small gaps
        let promptStartThreshold = 19 * 60  // 1140 seconds (95%)

        let displayMinutes: Int
        if totalSeconds >= promptStartThreshold {
            // Worked essentially the whole block - credit full 20m
            displayMinutes = 20
        } else {
            // Round to nearest minute (30s+ rounds up) - matches Stats/Overview/TimeBreakdown
            displayMinutes = (totalSeconds + 30) / 60
        }

        // Only show if there's time tracked and block is done or has data
        // Don't show if timer is actively running
        let hasAnyData = hasSegments || (block?.usedSeconds ?? 0) > 0
        if displayMinutes <= 0 || (!isDone && !hasAnyData) || isTimerActiveOnThisBlock {
            return nil
        }

        return displayMinutes
    }

    private var opacity: Double {
        if isDone || isCurrentBlock || isPlanned || isTimerActiveOnThisBlock {
            return 1.0
        }
        // Blocks with recorded segments (e.g. stopped mid-way) should show
        // their fill at full color, not muted
        if hasSegments {
            return 1.0
        }
        return 0.5
    }

    // Determine text color based on background for proper contrast
    private var labelTextColor: Color {
        if isDone {
            // Done blocks have colored fill - use black for contrast
            return .black
        }
        // For all other states (planned, active, idle), use primary color
        // which adapts to light/dark mode
        return .primary
    }

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)

            // Segment-based fill - renders each work/break segment with its category color
            // IMPORTANT: Skipped blocks should NOT show any fill (even if they have legacy data)
            // NOTE: Fills are rendered BEFORE border so border shows on top with current color
            if isSkipped {
                // No fill for skipped blocks - they show empty
            } else if isTimerActiveOnThisBlock {
                // Live segment fill - render previous and current session segments separately
                // Previous segments use 1/1200 scale, live segments use sessionScaleFactor
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Calculate total fill to determine if we're at 100%
                        let previousScale = 1.0 / 1200.0
                        let liveStartOffset = timerManager.previousVisualProportion
                        // Scale fill so it visually reaches the edge exactly when timer hits 0
                        // Corner radius makes ~97.5% visual look full, so we use 0.975 scale
                        // At 100% actual fill, visual = 97.5% which looks full due to corner radius
                        let visualScale = 0.975

                        // 1. Render previous segments (from earlier timer sessions)
                        ForEach(Array(timerManager.previousSegments.enumerated()), id: \.offset) { index, segment in
                            let segmentStart = segmentStartProportion(at: index, segments: timerManager.previousSegments, scaleFactor: previousScale) * visualScale
                            let segmentWidth = Double(segment.seconds) * previousScale * visualScale

                            Rectangle()
                                .fill(colorForSegment(segment))
                                .frame(width: geo.size.width * min(segmentWidth, 1.0 - segmentStart))
                                .offset(x: geo.size.width * segmentStart)
                        }

                        // 2. Render live segments (current session) starting after previous segments
                        let liveSegs = timerManager.liveSegmentsIncludingCurrent
                        // Only apply minimum fill in the first 60s of a timer session
                        // to avoid a visible jump when switching categories mid-block
                        let applyMinFill = timerManager.secondsUsed < 60
                        ForEach(Array(liveSegs.enumerated()), id: \.offset) { index, segment in
                            let segmentStart = liveStartOffset * visualScale + segmentStartProportion(at: index, segments: liveSegs, scaleFactor: timerManager.sessionScaleFactor) * visualScale
                            let rawWidth = geo.size.width * min(Double(segment.seconds) * timerManager.sessionScaleFactor * visualScale, 1.0 - segmentStart)
                            let isLastSegment = index == liveSegs.count - 1
                            let fillWidth = (isLastSegment && applyMinFill) ? max(4.5, rawWidth) : rawWidth

                            Rectangle()
                                .fill(colorForSegment(segment))
                                .frame(width: fillWidth)
                                .offset(x: geo.size.width * min(segmentStart, 1.0))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let segments = block?.segments, !segments.isEmpty {
                // Block with saved segments (done OR stopped mid-way) - render saved segments
                // For done blocks: use scaleFactor that fills to 100% (matches live rendering)
                // For non-done blocks: use standard 1/1200 to show actual proportion
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Calculate total seconds from all segments
                        let totalSegmentSeconds = segments.reduce(0) { $0 + $1.seconds }
                        // Done blocks fill to 100%, non-done show actual proportion
                        let scaleFactor = isDone && totalSegmentSeconds > 0
                            ? 1.0 / Double(totalSegmentSeconds)
                            : 1.0 / 1200.0

                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            let segmentStart = segmentStartProportion(at: index, segments: segments, scaleFactor: scaleFactor)
                            let segmentWidth = Double(segment.seconds) * scaleFactor

                            Rectangle()
                                .fill(colorForSegment(segment))
                                .frame(width: geo.size.width * min(segmentWidth, 1.0 - segmentStart))
                                .offset(x: geo.size.width * segmentStart)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if isDone, let catColor = categoryColor {
                // Done block without segments but HAS category - fill with category color (legacy)
                // Only render if we have an actual category, otherwise it's likely corrupted data
                Rectangle()
                    .fill(catColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let progress = block?.progress, progress > 0, let catColor = categoryColor {
                // Only show progress fill if we have a category (otherwise looks wrong)
                // Saved progress (legacy fallback)
                GeometryReader { geo in
                    Rectangle()
                        .fill(catColor.opacity(0.8))
                        .frame(width: geo.size.width * (progress / 100))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Border - drawn ON TOP of fills so current segment color shows all around
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: borderWidth)

            // Top row: block number and time
            HStack {
                Text("\(displayNumber)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isDone ? labelTextColor.opacity(0.7) : .secondary)

                Spacer()

                Text(timeString)
                    .font(.system(size: 9))
                    .foregroundStyle(isDone ? labelTextColor.opacity(0.7) : .secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 5)
            .padding(.top, 3)

            // Center: main content (label/status)
            Group {
                if isMuted && block?.isActivated != true && !isDone && !hasSegments {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.gray.opacity(0.5))
                } else if isSkipped && !hasSegments {
                    Text(showMotivationalInsults ? getSkippedInsult(blockIndex: blockIndex) : "SKIPPED")
                        .font(.system(size: showMotivationalInsults ? 7 : 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(showMotivationalInsults ? Color.red : Color(.label))
                } else if isSkipped && hasSegments, let doneLabel = doneBlockDisplayLabel {
                    // Skipped blocks with data should show their label, not "SKIPPED"
                    Text(doneLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.3)
                        .lineLimit(1)
                        .foregroundStyle(labelTextColor)
                } else if isTimerActiveOnThisBlock {
                    // Show timer label/category (may be more up-to-date than block data)
                    if let timerLabel = timerManager.currentLabel, !timerLabel.isEmpty {
                        Text(timerLabel.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.3)
                            .lineLimit(1)
                            .foregroundStyle(labelTextColor)
                    } else if let timerCatLabel = timerCategoryLabel {
                        Text(timerCatLabel.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.3)
                            .lineLimit(1)
                            .foregroundStyle(labelTextColor)
                    } else if timerManager.isBreak {
                        Text("BREAK")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.3)
                            .foregroundStyle(.red)
                    }
                } else if isDone, let doneLabel = doneBlockDisplayLabel {
                    // Done blocks: show dominant label with +brk suffix if break was taken
                    Text(doneLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.3)
                        .lineLimit(1)
                        .foregroundStyle(labelTextColor)
                } else if let label = block?.label, !label.isEmpty {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.3)
                        .lineLimit(1)
                        .foregroundStyle(labelTextColor)
                } else if let catLabel = categoryLabel {
                    Text(catLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.3)
                        .lineLimit(1)
                        .foregroundStyle(labelTextColor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 5)

            // Bottom row: status indicators
            HStack {
                Spacer()

                if isPlanned && !isTimerActiveOnThisBlock {
                    HStack(spacing: 2) {
                        Text("PLANNED")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(categoryColor ?? .orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 5)
            .padding(.bottom, 3)

            // Minutes indicator (bottom right, separate from other indicators)
            // Only shows when there's tracked time from segments
            if let displayMinutes = calculateDisplayMinutes() {
                Text("\(displayMinutes)m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(labelTextColor.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
            }
        }
        .aspectRatio(2.8, contentMode: .fit) // Wide rectangular blocks (3 per row = 1 hour)
        .opacity(opacity)
    }
}

#Preview {
    ScrollView {
        BlockGridView(
            blocks: (0..<72).map { index in
                Block(
                    id: UUID().uuidString,
                    userId: "",
                    date: "2024-01-01",
                    blockIndex: index,
                    isMuted: index < 24,
                    isActivated: false,
                    category: index % 5 == 0 ? "work" : nil,
                    label: index % 7 == 0 ? "Task" : nil,
                    note: nil,
                    status: index < 30 ? .done : (index == 30 ? .idle : (index == 31 ? .planned : .idle)),
                    progress: 0,
                    breakProgress: 0,
                    runs: nil,
                    activeRunSnapshot: nil,
                    segments: [],
                    usedSeconds: 0,
                    createdAt: "",
                    updatedAt: ""
                )
            },
            date: Date(),
            selectedBlockIndex: .constant(nil)
        )
        .environmentObject(BlockManager())
        .padding()
    }
}
