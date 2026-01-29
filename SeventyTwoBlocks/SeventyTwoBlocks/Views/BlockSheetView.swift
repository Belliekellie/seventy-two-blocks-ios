import SwiftUI
import Combine

struct BlockSheetView: View {
    let blockIndex: Int
    let date: String
    @EnvironmentObject var blockManager: BlockManager
    @EnvironmentObject var timerManager: TimerManager
    @Environment(\.dismiss) private var dismiss

    @State private var category: String?
    @State private var label: String = ""
    @State private var status: BlockStatus = .idle
    @State private var showResetConfirmation = false
    @State private var showSkipConfirmation = false
    @State private var hasChanges = false
    @State private var initializedFromBlock = false
    @State private var remainingSeconds: Int = 1200  // Updated by timer
    @State private var shouldDismiss = false
    @FocusState private var labelFieldFocused: Bool

    // Timer for pre-start countdown display
    private let countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Get the current block from blockManager (always fresh)
    private var block: Block {
        blockManager.blocks.first { $0.blockIndex == blockIndex } ?? createPlaceholderBlock()
    }

    private func createPlaceholderBlock() -> Block {
        Block(
            id: UUID().uuidString,
            userId: "",
            date: date,
            blockIndex: blockIndex,
            isMuted: false,
            isActivated: false,
            category: nil,
            label: nil,
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
    }

    // Favorite labels from BlockManager (synced with Supabase)
    private var favoriteLabels: [String] {
        blockManager.favoriteLabels
    }

    // Category-specific labels
    private var categoryLabels: [String] {
        guard let categoryId = category else {
            print("📋 categoryLabels: no category selected")
            return []
        }
        guard let cat = blockManager.categories.first(where: { $0.id == categoryId }) else {
            print("📋 categoryLabels: category '\(categoryId)' not found in \(blockManager.categories.map { $0.id })")
            return []
        }
        let labels = (cat.labels ?? []).filter { !favoriteLabels.contains($0) }
        print("📋 categoryLabels for '\(categoryId)': \(labels) (raw: \(cat.labels ?? []))")
        return labels
    }

    private var blockTime: String {
        "\(Block.blockToTime(block.blockIndex)) - \(Block.blockEndTime(block.blockIndex))"
    }

    @AppStorage("dayStartHour") private var dayStartHour = 6

    /// Returns the "logical today" date string, accounting for dayStartHour setting
    private var todayString: String {
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
        return formatter.string(from: logicalDate)
    }

    /// Whether we're viewing today's date (not a past or future day)
    private var isViewingToday: Bool {
        date == todayString
    }

    /// Whether we're viewing a past day (before today)
    private var isViewingPastDay: Bool {
        date < todayString
    }

    /// Whether we're viewing a future day (after today)
    private var isViewingFutureDay: Bool {
        date > todayString
    }

    /// Is this the current block RIGHT NOW? Only true if viewing today
    private var isCurrentBlock: Bool {
        isViewingToday && block.blockIndex == Block.getCurrentBlockIndex()
    }

    /// Past block - when viewing today with an earlier block index
    private var isPastBlock: Bool {
        if !isViewingToday {
            return false  // Other days don't have "past" blocks in the timer sense
        }
        return block.blockIndex < Block.getCurrentBlockIndex()
    }

    /// Future block - when not viewing today, or when viewing today with a later block index
    private var isFutureBlock: Bool {
        if !isViewingToday {
            return true  // All blocks on other days are "future" (can't start timer)
        }
        return block.blockIndex > Block.getCurrentBlockIndex()
    }

    /// Timer is running for this block - only possible when viewing today
    private var isTimerRunningForThisBlock: Bool {
        isViewingToday && timerManager.isActive && timerManager.currentBlockIndex == block.blockIndex
    }

    private var categoryColor: Color {
        guard let categoryId = category,
              let cat = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return .blue
        }
        return cat.swiftUIColor
    }

    private var categoryName: String? {
        guard let categoryId = category,
              let cat = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return nil
        }
        return cat.label
    }

    /// Check if block has recorded time/work data that would be lost if skipped
    private var blockHasRecordedData: Bool {
        !block.segments.isEmpty || block.usedSeconds > 0 || block.progress > 0
    }

    /// Formatted remaining time in this block (MM:SS)
    private var formattedRemainingTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // Maximum characters for a label (keeps text fitting neatly on block grid)
    private let maxLabelLength = 14

    // Normalize label (trim whitespace, convert empty to nil)
    private func normalizeLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                // Block info section
                Section {
                    HStack {
                        Text("Block \(Block.displayBlockNumber(block.blockIndex))")
                            .font(.headline)
                        Spacer()
                        Text(blockTime)
                            .foregroundStyle(.secondary)
                    }
                }

                // Time breakdown at top for past/done blocks (most important info)
                if isPastBlock || isViewingPastDay || block.status == .done || block.status == .skipped {
                    Section {
                        TimeBreakdownView(
                            block: block,
                            categories: blockManager.categories,
                            categoryColor: categoryColor,
                            isPastBlock: true,
                            isTimerRunning: false,
                            onSaveSegments: { updatedSegments in
                                Task {
                                    await saveSegments(updatedSegments)
                                }
                            }
                        )
                    } header: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption)
                            Text("Time Breakdown")
                        }
                    }
                }

                // Timer section (hidden for past/done/skipped blocks — no useful info to show)
                if !isPastBlock && !isViewingPastDay && block.status != .done && block.status != .skipped {
                Section("Timer") {
                    VStack(spacing: 16) {
                        // Time display
                        HStack {
                            Image(systemName: timerManager.isBreak ? "cup.and.saucer.fill" : "clock.fill")
                                .foregroundStyle(timerManager.isBreak ? .red : categoryColor)

                            if isTimerRunningForThisBlock {
                                Text(timerManager.formattedTimeLeft)
                                    .font(.system(.title, design: .monospaced))
                                    .fontWeight(.medium)
                            } else {
                                Text(formattedRemainingTime)
                                    .font(.system(.title, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Progress indicator
                            if isTimerRunningForThisBlock {
                                Text("\(Int(timerManager.progress))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Progress bar
                        if isTimerRunningForThisBlock {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 8)

                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(timerManager.isBreak ? Color.red : categoryColor)
                                        .frame(width: geo.size.width * (timerManager.progress / 100), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }

                        // Control buttons
                        HStack(spacing: 12) {
                            if isTimerRunningForThisBlock {
                                // Pause/Stop buttons
                                Button(action: {
                                    timerManager.pauseTimer()
                                    dismiss()
                                }) {
                                    HStack {
                                        Image(systemName: "pause.fill")
                                        Text("Pause")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                Button(action: {
                                    timerManager.stopTimer(markComplete: true)
                                    dismiss()
                                }) {
                                    HStack {
                                        Image(systemName: "stop.fill")
                                        Text("Stop")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.15))
                                    .foregroundStyle(.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            } else if isViewingToday && !timerManager.isActive && timerManager.currentBlockIndex == block.blockIndex {
                                // Paused (only applies when viewing today)
                                Button(action: {
                                    timerManager.resumeTimer()
                                }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Resume")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(categoryColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            } else if isViewingPastDay {
                                // Viewing a past day - can't start timer
                                VStack(spacing: 4) {
                                    Text("Past day")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("Timers can only be started on today's blocks")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            } else if isViewingFutureDay {
                                // Viewing a future day - can't start timer
                                VStack(spacing: 4) {
                                    Text("Future day")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("Set a category and label to plan this block")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            } else if isFutureBlock {
                                // Future block on today - can't start yet
                                VStack(spacing: 4) {
                                    Text("Future block")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("Set a category and label to plan this block")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            } else if isPastBlock {
                                // Past block on today - can't start timer
                                VStack(spacing: 4) {
                                    Text("Block has passed")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("Timers can only run on the current block")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            } else {
                                // Start button (current block only)
                                Button(action: {
                                    startTimer()
                                }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Start Timer")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(categoryColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Work/Break toggle (when timer is running)
                        if isTimerRunningForThisBlock {
                            HStack(spacing: 12) {
                                Button(action: {
                                    if timerManager.isBreak {
                                        timerManager.switchToWork()
                                        dismiss()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "laptopcomputer")
                                        Text("Work")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(!timerManager.isBreak ? categoryColor.opacity(0.2) : Color.gray.opacity(0.1))
                                    .foregroundStyle(!timerManager.isBreak ? categoryColor : .secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(!timerManager.isBreak ? categoryColor : .clear, lineWidth: 2)
                                    )
                                }

                                Button(action: {
                                    if !timerManager.isBreak {
                                        timerManager.switchToBreak()
                                        dismiss()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "cup.and.saucer.fill")
                                        Text("Break")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(timerManager.isBreak ? Color.red.opacity(0.2) : Color.gray.opacity(0.1))
                                    .foregroundStyle(timerManager.isBreak ? .red : .secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(timerManager.isBreak ? Color.red : .clear, lineWidth: 2)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                } // end if !isPastBlock && !isViewingPastDay && !done/skipped

                // Category section
                Section {
                    if blockManager.categories.isEmpty {
                        Text("Loading categories...")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(blockManager.categories) { cat in
                                Button {
                                    let newCategory = category == cat.id ? nil : cat.id
                                    category = newCategory
                                    hasChanges = true
                                    // Update timer category if running (creates segment boundary)
                                    if isTimerRunningForThisBlock {
                                        timerManager.updateCategory(newCategory, label: normalizeLabel(label))
                                    }
                                } label: {
                                    Text(cat.label)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            category == cat.id
                                                ? cat.swiftUIColor
                                                : cat.swiftUIColor.opacity(0.15)
                                        )
                                        .foregroundStyle(
                                            category == cat.id
                                                ? .white
                                                : cat.swiftUIColor
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(
                                                    cat.swiftUIColor,
                                                    lineWidth: category == cat.id ? 2 : 1
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Category")
                } footer: {
                    Text("Tap to select, tap again to deselect")
                        .font(.caption2)
                }

                // Label section with favorites and presets
                Section {
                    // Text input with favorite toggle
                    HStack {
                        TextField("What are you working on?", text: $label)
                            .focused($labelFieldFocused)
                            .submitLabel(.done)
                            #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            #endif
                            .onChange(of: label) { _, newValue in
                                // Enforce character limit
                                if newValue.count > maxLabelLength {
                                    label = String(newValue.prefix(maxLabelLength))
                                    return // onChange will fire again with truncated value
                                }
                                hasChanges = true
                                // Update timer label if running
                                if isTimerRunningForThisBlock {
                                    timerManager.currentLabel = normalizeLabel(newValue)
                                }
                            }
                            .onSubmit {
                                // Save on Enter/Return key
                                labelFieldFocused = false
                                Task {
                                    await saveBlock()
                                    dismiss()
                                }
                            }

                        // Star button to toggle favorite
                        if let normalizedLabel = normalizeLabel(label) {
                            Button {
                                Task {
                                    await blockManager.toggleFavoriteLabel(normalizedLabel)
                                }
                            } label: {
                                Image(systemName: blockManager.favoriteLabels.contains(normalizedLabel) ? "star.fill" : "star")
                                    .foregroundStyle(blockManager.favoriteLabels.contains(normalizedLabel) ? .yellow : .gray)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Favorite labels
                    if !favoriteLabels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                Text("Favourites")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            FlowLayout(spacing: 6) {
                                ForEach(favoriteLabels, id: \.self) { favLabel in
                                    Button {
                                        // Toggle behavior - if already selected, clear it
                                        if label == favLabel {
                                            label = ""
                                            if isTimerRunningForThisBlock {
                                                timerManager.currentLabel = nil
                                            }
                                        } else {
                                            label = favLabel
                                            if isTimerRunningForThisBlock {
                                                timerManager.currentLabel = favLabel
                                            }
                                            // Auto-save and dismiss when selecting a label
                                            Task {
                                                await saveBlock()
                                                dismiss()
                                            }
                                        }
                                        hasChanges = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(favLabel)
                                                .font(.caption)
                                            if label == favLabel {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(label == favLabel ? categoryColor.opacity(0.2) : Color.gray.opacity(0.1))
                                        .foregroundStyle(label == favLabel ? categoryColor : .primary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(label == favLabel ? categoryColor : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        // Remove from favorites
                                        Button(role: .destructive) {
                                            Task {
                                                await blockManager.removeFavoriteLabel(favLabel)
                                            }
                                        } label: {
                                            Label("Remove from Favourites", systemImage: "star.slash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Category-specific labels
                    if !categoryLabels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "tag")
                                    .font(.caption)
                                    .foregroundStyle(categoryColor)
                                Text(categoryName ?? "Recent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            FlowLayout(spacing: 6) {
                                ForEach(categoryLabels, id: \.self) { catLabel in
                                    Button {
                                        // Toggle behavior
                                        if label == catLabel {
                                            label = ""
                                            if isTimerRunningForThisBlock {
                                                timerManager.currentLabel = nil
                                            }
                                        } else {
                                            label = catLabel
                                            if isTimerRunningForThisBlock {
                                                timerManager.currentLabel = catLabel
                                            }
                                            // Auto-save and dismiss when selecting a label
                                            Task {
                                                await saveBlock()
                                                dismiss()
                                            }
                                        }
                                        hasChanges = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(catLabel)
                                                .font(.caption)
                                            if label == catLabel {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(label == catLabel ? categoryColor.opacity(0.2) : Color.gray.opacity(0.1))
                                        .foregroundStyle(label == catLabel ? categoryColor : .primary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(label == catLabel ? categoryColor : Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        // Add to favorites
                                        Button {
                                            Task {
                                                await blockManager.toggleFavoriteLabel(catLabel)
                                            }
                                        } label: {
                                            Label(
                                                blockManager.favoriteLabels.contains(catLabel) ? "Remove from Favourites" : "Add to Favourites",
                                                systemImage: blockManager.favoriteLabels.contains(catLabel) ? "star.slash" : "star"
                                            )
                                        }

                                        Divider()

                                        // Remove from this category
                                        if let categoryId = category {
                                            Button(role: .destructive) {
                                                Task {
                                                    await blockManager.removeLabelFromCategory(categoryId: categoryId, label: catLabel)
                                                }
                                            } label: {
                                                Label("Remove from \(categoryName ?? "Category")", systemImage: "minus.circle")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Label")
                } footer: {
                    Text("\(label.count)/\(maxLabelLength) characters")
                        .font(.caption2)
                        .foregroundStyle(label.count >= maxLabelLength ? .orange : .secondary)
                }

                // Time breakdown - show after label section (only for active/future blocks;
                // past/done/skipped blocks have it at the top of the sheet)
                if !isPastBlock && !isViewingPastDay && block.status != .done && block.status != .skipped {
                    Section {
                        TimeBreakdownView(
                            block: block,
                            categories: blockManager.categories,
                            categoryColor: categoryColor,
                            isPastBlock: false,
                            isTimerRunning: isTimerRunningForThisBlock,
                            onSaveSegments: { updatedSegments in
                                Task {
                                    await saveSegments(updatedSegments)
                                }
                            }
                        )
                    } header: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption)
                            Text("Time Breakdown")
                        }
                    }
                }

                // Schedule Break button (for future blocks without timer)
                if isFutureBlock && !isTimerRunningForThisBlock {
                    Section {
                        Button {
                            // Schedule a break for this future block
                            category = "break"
                            label = "Break"
                            status = .planned
                            hasChanges = true
                        } label: {
                            HStack {
                                Image(systemName: "cup.and.saucer.fill")
                                Text(category == "break" ? "Unschedule Break" : "Schedule Break")
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.red)
                        }
                    }
                }

                // Status section (for past blocks or manual marking)
                if !isTimerRunningForThisBlock {
                    Section("Mark as") {
                        HStack(spacing: 12) {
                            StatusButton(
                                title: "Done",
                                icon: "checkmark",
                                isSelected: status == .done,
                                color: .green
                            ) {
                                status = .done
                                hasChanges = true
                            }

                            StatusButton(
                                title: "Skipped",
                                icon: "xmark",
                                isSelected: status == .skipped,
                                color: .red
                            ) {
                                if blockHasRecordedData && status != .skipped {
                                    // Show warning if block has data
                                    showSkipConfirmation = true
                                } else {
                                    status = .skipped
                                    hasChanges = true
                                }
                            }

                            if isFutureBlock {
                                StatusButton(
                                    title: "Planned",
                                    icon: "clock",
                                    isSelected: status == .planned,
                                    color: .orange
                                ) {
                                    status = .planned
                                    hasChanges = true
                                }
                            }
                        }
                    }
                }

                // Reset block button
                if block.status != .idle || block.category != nil || block.label != nil || block.progress > 0 {
                    Section {
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset Block")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } footer: {
                        Text("Clears all data from this block")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle(isViewingPastDay ? "Past Block" : (isFutureBlock ? "Future Block" : "Block Details"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        shouldDismiss = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveBlock()
                            shouldDismiss = true
                        }
                    }
                }
            }
            .onChange(of: shouldDismiss) { _, newValue in
                if newValue { dismiss() }
            }
            .onAppear {
                // Only initialize state once when sheet first appears
                guard !initializedFromBlock else {
                    print("🔵 BlockSheet onAppear - already initialized, skipping")
                    return
                }
                initializedFromBlock = true

                print("🔵 BlockSheet onAppear - block \(block.blockIndex)")
                print("🔵 Block id: \(block.id)")
                print("🔵 Block category: \(block.category ?? "nil"), label: \(block.label ?? "nil")")
                print("🔵 Setting label state to: '\(block.label ?? "")'")
                category = block.category
                label = block.label ?? ""
                status = block.status

                // Initialize remaining seconds based on block time
                remainingSeconds = Block.remainingSecondsInBlock(blockIndex)
            }
            .onReceive(countdownTimer) { _ in
                // Only tick down if timer isn't running for this block
                if !isTimerRunningForThisBlock {
                    remainingSeconds = Block.remainingSecondsInBlock(blockIndex)
                }
            }
            .task {
                print("🔵 BlockSheet .task - loading categories and favorites...")
                await blockManager.loadCategories()
                await blockManager.loadFavoriteLabels()
                print("🔵 Categories loaded: \(blockManager.categories.count), Favorites: \(blockManager.favoriteLabels.count)")
                for cat in blockManager.categories {
                    print("🔵   \(cat.id): \(cat.labels?.count ?? 0) labels")
                }
            }
            .alert("Reset Block?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    Task {
                        await resetBlock()
                        dismiss()
                    }
                }
            } message: {
                Text("This will clear all data from this block including category, label, and progress.")
            }
            .alert("Mark as Skipped?", isPresented: $showSkipConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Skip & Clear Data", role: .destructive) {
                    status = .skipped
                    hasChanges = true
                }
            } message: {
                Text("This block has recorded time data. Marking it as skipped will remove this data from your totals.")
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func startTimer() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        // Save block and handle night block activation
        Task {
            await saveBlock()
            // If this is a night block, activate it and auto-skip previous unused night blocks
            await blockManager.activateBlockForTimer(blockIndex: block.blockIndex)
        }

        // Duration calculated automatically based on block boundary
        // Pass existing segments so timer continues from where it left off
        timerManager.startTimer(
            for: block.blockIndex,
            date: dateString,
            isBreakMode: false,
            category: category,
            label: normalizeLabel(label),
            existingSegments: block.segments
        )

        // Schedule notification at actual block end time
        NotificationManager.shared.scheduleTimerComplete(
            at: Block.blockEndDate(for: block.blockIndex),
            blockIndex: block.blockIndex,
            isBreak: false
        )

        // Close the sheet
        dismiss()
    }

    private func saveBlock() async {
        let normalizedLabel = normalizeLabel(label)
        print("💾 BlockSheetView.saveBlock() called")
        print("💾   Current label state: '\(label)'")
        print("💾   Normalized label: '\(normalizedLabel ?? "nil")'")
        print("💾   Category: '\(category ?? "nil")'")
        print("💾   Original block label: '\(block.label ?? "nil")'")
        print("💾   Timer running for this block: \(isTimerRunningForThisBlock)")

        var updatedBlock = block
        updatedBlock.category = category
        updatedBlock.label = normalizedLabel

        // CRITICAL: When timer is running for this block, DON'T reset status or segments
        // Just update category/label metadata - the timer owns the progress data
        if isTimerRunningForThisBlock {
            print("💾   Timer active - preserving progress and segments, just updating metadata")
            // Keep existing status, progress, segments - timer will save these when it stops
            // Only update the current segments for visual consistency
            updatedBlock.segments = timerManager.allSegmentsIncludingCurrent
            updatedBlock.usedSeconds = timerManager.secondsUsed
            // Don't change status while timer is running
        } else {
            // Timer not running - safe to update status
            updatedBlock.status = status

            // If setting to planned for future block
            if isFutureBlock && (category != nil || normalizedLabel != nil) && status == .idle {
                updatedBlock.status = .planned
            }
        }

        print("💾   Updated block label: '\(updatedBlock.label ?? "nil")'")

        await blockManager.saveBlock(updatedBlock)

        // Auto-save label to category's preset list (if category is set and label is new)
        if let categoryId = category,
           let normalizedLabel = normalizeLabel(label),
           !normalizedLabel.isEmpty {
            print("💾 Saving label '\(normalizedLabel)' to category '\(categoryId)'")
            await blockManager.addLabelToCategory(categoryId: categoryId, label: normalizedLabel)
            print("💾 Label save completed")
        }

        // Auto-start timer ONLY if:
        // 1. This is the current block
        // 2. NO timer is running anywhere (not just this block)
        // 3. We have category/label to start with
        if isCurrentBlock && !timerManager.isActive && (category != nil || normalizeLabel(label) != nil) {
            print("🚀 Auto-starting timer for current block")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: Date())

            let isBreakMode = category == "break"

            // Duration calculated automatically based on block boundary
            // Pass existing segments so timer continues from where it left off
            timerManager.startTimer(
                for: block.blockIndex,
                date: dateString,
                isBreakMode: isBreakMode,
                category: category,
                label: normalizeLabel(label),
                existingSegments: isBreakMode ? [] : block.segments  // Only preserve work segments for work mode
            )

            // Schedule notification at actual block end time (or fixed duration for breaks)
            let notificationTime = isBreakMode
                ? Date().addingTimeInterval(300)  // 5 min for breaks
                : Block.blockEndDate(for: block.blockIndex)
            NotificationManager.shared.scheduleTimerComplete(
                at: notificationTime,
                blockIndex: block.blockIndex,
                isBreak: isBreakMode
            )
        }
    }

    private func resetBlock() async {
        var resetBlock = block
        resetBlock.category = nil
        resetBlock.label = nil
        resetBlock.note = nil
        resetBlock.status = .idle
        resetBlock.progress = 0
        resetBlock.breakProgress = 0
        resetBlock.usedSeconds = 0
        resetBlock.runs = nil
        resetBlock.activeRunSnapshot = nil
        resetBlock.segments = []
        resetBlock.isActivated = false
        // Preserve isMuted (sleep block status)

        await blockManager.saveBlock(resetBlock)
        await blockManager.reloadBlocks()
    }

    private func saveSegments(_ updatedSegments: [BlockSegment]) async {
        var updatedBlock = block
        updatedBlock.segments = updatedSegments

        // Recalculate usedSeconds from segments
        updatedBlock.usedSeconds = updatedSegments.reduce(0) { $0 + $1.seconds }

        // Update the block's top-level category and label to match the dominant work segment
        // so the block grid fill color reflects the edited data
        let workSegments = updatedSegments.filter { $0.type == .work && $0.seconds > 0 }
        if let dominant = workSegments.max(by: { $0.seconds < $1.seconds }) {
            updatedBlock.category = dominant.category
            updatedBlock.label = dominant.label
            // Also update local state so the sheet reflects the change
            category = dominant.category
            label = dominant.label ?? ""
            hasChanges = true
        }

        await blockManager.saveBlock(updatedBlock)
        await blockManager.reloadBlocks()
    }
}

// MARK: - Time Breakdown View

struct TimeBreakdownView: View {
    let block: Block
    let categories: [Category]
    let categoryColor: Color
    let isPastBlock: Bool
    var isTimerRunning: Bool = false
    var onSaveSegments: (([BlockSegment]) -> Void)?

    @State private var isEditing = false
    @State private var editedSegments: [BlockSegment] = []

    private var hasData: Bool {
        block.usedSeconds > 0 || block.progress > 0 || !block.segments.isEmpty
    }

    private var workSegments: [BlockSegment] {
        block.segments.filter { $0.type == .work }
    }

    // Aggregate work entries by category+label
    private var workEntries: [(category: String?, label: String?, seconds: Int, percentage: Int)] {
        var entries: [String: (category: String?, label: String?, seconds: Int)] = [:]

        for segment in block.segments where segment.type == .work {
            let key = "\(segment.category ?? "none")|\(segment.label ?? "none")"
            if var existing = entries[key] {
                existing.seconds += segment.seconds
                entries[key] = existing
            } else {
                entries[key] = (segment.category, segment.label, segment.seconds)
            }
        }

        let totalWorkSeconds = entries.values.reduce(0) { $0 + $1.seconds }

        return entries.values
            .map { entry in
                let percentage = totalWorkSeconds > 0 ? Int(Double(entry.seconds) / Double(totalWorkSeconds) * 100) : 0
                return (entry.category, entry.label, entry.seconds, percentage)
            }
            .sorted { $0.seconds > $1.seconds }
    }

    private var breakSeconds: Int {
        block.segments.filter { $0.type == .break }.reduce(0) { $0 + $1.seconds }
    }

    private var totalSeconds: Int {
        block.segments.reduce(0) { $0 + $1.seconds }
    }

    // Adjustment factor for prompt-start (if started early, round to 20m)
    private var adjustmentFactor: Double {
        guard totalSeconds > 0 else { return 1.0 }
        let blockDuration = 20 * 60 // 20 minutes
        if totalSeconds >= blockDuration - 60 { // Within 1 minute of full block
            return Double(blockDuration) / Double(totalSeconds)
        }
        return 1.0
    }

    private var adjustedTotalSeconds: Int {
        Int(Double(totalSeconds) * adjustmentFactor)
    }

    private func getCategoryColor(_ categoryId: String?) -> Color {
        guard let id = categoryId,
              let cat = categories.first(where: { $0.id == id }) else {
            return .gray
        }
        return cat.swiftUIColor
    }

    private func getCategoryName(_ categoryId: String?) -> String {
        guard let id = categoryId,
              let cat = categories.first(where: { $0.id == id }) else {
            return "Uncategorised"
        }
        return cat.label
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds == 0 {
            return "0m"
        }

        // Under 30 seconds shows as "<1m" to indicate some work was done
        if seconds > 0 && seconds < 30 {
            return "<1m"
        }

        // Round to nearest minute (30s+ rounds up)
        let totalMinutes = (seconds + 30) / 60

        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let remainingMins = totalMinutes % 60
            return "\(hours)h \(remainingMins)m"
        }
        return "\(totalMinutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isTimerRunning {
                // Timer is active - don't show breakdown (it would get overwritten)
                Text("Time breakdown will be available when this block completes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else if isEditing {
                // EDITING MODE - show individual segment editors (work + break)
                Text("Edit category and label for each segment:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(editedSegments.enumerated()), id: \.offset) { index, segment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Segment \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatDuration(Int(Double(segment.seconds) * adjustmentFactor)))
                                .font(.caption.weight(.medium))
                        }

                        HStack(spacing: 8) {
                            // Category picker (includes Break option)
                            Menu {
                                Button {
                                    editedSegments[index] = BlockSegment(
                                        type: .break,
                                        seconds: segment.seconds,
                                        category: nil,
                                        label: nil,
                                        startElapsed: segment.startElapsed
                                    )
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color.gray)
                                            .frame(width: 8, height: 8)
                                        Text("Break")
                                    }
                                }
                                ForEach(categories) { cat in
                                    Button {
                                        editedSegments[index] = BlockSegment(
                                            type: .work,
                                            seconds: segment.seconds,
                                            category: cat.id,
                                            label: segment.type == .break ? nil : segment.label,
                                            startElapsed: segment.startElapsed
                                        )
                                    } label: {
                                        HStack {
                                            Circle()
                                                .fill(cat.swiftUIColor)
                                                .frame(width: 8, height: 8)
                                            Text(cat.label)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    if segment.type == .break {
                                        Circle()
                                            .fill(Color.gray)
                                            .frame(width: 8, height: 8)
                                        Text("Break")
                                            .font(.caption)
                                    } else {
                                        Circle()
                                            .fill(getCategoryColor(segment.category))
                                            .frame(width: 8, height: 8)
                                        Text(getCategoryName(segment.category))
                                            .font(.caption)
                                    }
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            // Label input (disabled for break segments)
                            if segment.type == .work {
                                TextField("Label", text: Binding(
                                    get: { segment.label ?? "" },
                                    set: { editedSegments[index].label = $0.isEmpty ? nil : $0 }
                                ))
                                .font(.caption)
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if index < editedSegments.count - 1 {
                        Divider()
                    }
                }

                // Cancel / Save buttons
                HStack(spacing: 12) {
                    Button {
                        isEditing = false
                        editedSegments = []
                    } label: {
                        Text("Cancel")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSaveSegments?(editedSegments)
                        isEditing = false
                        editedSegments = []
                    } label: {
                        Text("Save Changes")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(categoryColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

            } else if !hasData {
                // Placeholder when no data yet
                Text(isPastBlock ? "No time recorded" : "Available after block time passes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else if block.segments.isEmpty && block.usedSeconds > 0 {
                // Fallback: block has usedSeconds but no segment data (legacy or manual done)
                HStack(spacing: 8) {
                    Circle()
                        .fill(getCategoryColor(block.category))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(getCategoryName(block.category))
                            .font(.subheadline.weight(.medium))
                        if let label = block.label, !label.isEmpty {
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Round up to 20m if >= 95%
                    let displaySeconds = block.status == .done && block.usedSeconds >= 19 * 60 ? 20 * 60 : block.usedSeconds
                    Text(formatDuration(displaySeconds))
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                // AGGREGATED VIEW - work entries
                if !workEntries.isEmpty {
                    ForEach(Array(workEntries.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(getCategoryColor(entry.category))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(getCategoryName(entry.category))
                                    .font(.subheadline.weight(.medium))
                                if let label = entry.label, !label.isEmpty {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(formatDuration(Int(Double(entry.seconds) * adjustmentFactor)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("\(entry.percentage)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 35, alignment: .trailing)
                        }
                    }
                }

                // Break entry
                if breakSeconds >= 60 {
                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.caption)
                            .foregroundStyle(.red)

                        Text("Break")
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text(formatDuration(Int(Double(breakSeconds) * adjustmentFactor)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Total (only show if we have segment data)
                if totalSeconds > 0 {
                    Divider()

                    HStack {
                        Text("Total")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(formatDuration(adjustedTotalSeconds))
                            .font(.subheadline.weight(.semibold))
                    }

                    // Edit breakdown button
                    if !workSegments.isEmpty && onSaveSegments != nil {
                        Divider()

                        Button {
                            editedSegments = block.segments
                            isEditing = true
                        } label: {
                            HStack {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                Text("Edit breakdown")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Flow Layout for Label Chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Status Button

struct StatusButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.15))
            .foregroundStyle(isSelected ? color : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BlockSheetView(blockIndex: 30, date: "2024-01-01")
        .environmentObject(BlockManager())
        .environmentObject(TimerManager())
}
