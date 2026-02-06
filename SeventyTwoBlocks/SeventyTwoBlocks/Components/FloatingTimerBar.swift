import SwiftUI

struct FloatingTimerBar: View {
    @EnvironmentObject var timerManager: TimerManager
    @EnvironmentObject var blockManager: BlockManager

    private var currentBlock: Block? {
        guard let index = timerManager.currentBlockIndex else { return nil }
        return blockManager.blocks.first { $0.blockIndex == index }
    }

    private var timeString: String {
        let minutes = timerManager.timeLeft / 60
        let seconds = timerManager.timeLeft % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var blockDisplayNumber: Int {
        guard let index = timerManager.currentBlockIndex else { return 1 }
        // Convert to day-order display number (1-72)
        if index >= 24 && index <= 47 {
            return index - 24 + 1  // Morning: 1-24
        } else if index >= 48 && index <= 71 {
            return index - 48 + 25  // Afternoon: 25-48
        } else {
            return index + 49  // Night: 49-72
        }
    }

    private var blockTimeRange: String {
        guard let index = timerManager.currentBlockIndex else { return "" }
        let startMinutes = index * 20
        let endMinutes = (index + 1) * 20

        func formatTime(_ totalMinutes: Int) -> String {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            let hour12 = hours % 12 == 0 ? 12 : hours % 12
            let ampm = hours < 12 ? "am" : "pm"
            return "\(hour12):\(String(format: "%02d", mins))\(ampm)"
        }

        return "\(formatTime(startMinutes)) - \(formatTime(endMinutes))"
    }

    private var categoryColor: Color {
        if timerManager.isBreak {
            return .red
        }
        guard let categoryId = timerManager.currentCategory ?? currentBlock?.category,
              let category = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return Color(hue: 187/360, saturation: 0.70, brightness: 0.75)
        }
        return category.swiftUIColor
    }

    /// Color for the "Work" button when in break mode - uses last work category
    private var lastWorkCategoryColor: Color {
        guard let categoryId = timerManager.lastWorkCategory ?? timerManager.currentCategory ?? currentBlock?.category,
              let category = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return Color(hue: 187/360, saturation: 0.70, brightness: 0.75) // Default teal
        }
        return category.swiftUIColor
    }

    /// Whether the timer is paused - uses explicit state from TimerManager
    private var isPaused: Bool {
        timerManager.isPaused
    }

    /// Whether to show the floating bar (active OR paused)
    private var shouldShow: Bool {
        timerManager.isActive || timerManager.isPaused
    }

    /// Color for pause button - matches current work/break state
    private var pauseButtonColor: Color {
        if timerManager.isBreak {
            return .red
        }
        return categoryColor
    }

    // Progress as 0-1 fraction (timerManager.progress is 0-100)
    private var progressFraction: Double {
        timerManager.progress / 100.0
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
        // Fallback to current category color
        return categoryColor
    }

    /// Calculate the starting proportion (0..1) for a segment at a given index
    private func segmentStartProportion(at index: Int, segments: [BlockSegment], scaleFactor: Double) -> Double {
        var start: Double = 0
        for i in 0..<index {
            start += Double(segments[i].seconds) * scaleFactor
        }
        return min(start, 1.0)
    }

    var body: some View {
        if shouldShow {
            VStack(spacing: 10) {
                // Row 1: Timer info
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: isPaused ? "pause.circle.fill" : (timerManager.isBreak ? "cup.and.saucer.fill" : "clock.fill"))
                        .font(.title3)
                        .foregroundStyle(isPaused ? pauseButtonColor : (timerManager.isBreak ? .red : categoryColor))

                    // Block/Break label
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(timerManager.isBreak ? "Break" : "Block \(blockDisplayNumber)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            if isPaused {
                                Text("PAUSED")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(pauseButtonColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Text(blockTimeRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Countdown timer
                    Text(timeString)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(isPaused ? pauseButtonColor : (timerManager.timeLeft < 60 ? .red : (timerManager.isBreak ? .red : categoryColor)))
                }

                // Row 2: Multi-segment progress bar (shows work/break segments in their colors)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)

                        // Segment fills
                        let previousScale = 1.0 / 1200.0
                        let liveStartOffset = timerManager.previousVisualProportion
                        let liveSegs = timerManager.liveSegmentsIncludingCurrent

                        // 1. Render previous segments (from earlier timer sessions)
                        ForEach(Array(timerManager.previousSegments.enumerated()), id: \.element.compositeId) { index, segment in
                            let segmentStart = segmentStartProportion(at: index, segments: timerManager.previousSegments, scaleFactor: previousScale)
                            let segmentWidth = Double(segment.seconds) * previousScale

                            Rectangle()
                                .fill(colorForSegment(segment))
                                .frame(width: geo.size.width * min(segmentWidth, 1.0 - segmentStart), height: 6)
                                .offset(x: geo.size.width * segmentStart)
                        }

                        // 2. Render live segments (current session)
                        ForEach(Array(liveSegs.enumerated()), id: \.element.compositeId) { index, segment in
                            let segmentStart = liveStartOffset + segmentStartProportion(at: index, segments: liveSegs, scaleFactor: timerManager.sessionScaleFactor)
                            let segmentWidth = Double(segment.seconds) * timerManager.sessionScaleFactor

                            Rectangle()
                                .fill(colorForSegment(segment))
                                .frame(width: geo.size.width * min(segmentWidth, 1.0 - segmentStart), height: 6)
                                .offset(x: geo.size.width * min(segmentStart, 1.0))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 6)

                // Row 3: Control buttons (Break toggle, Pause/Resume, Stop)
                HStack(spacing: 8) {
                    // Break toggle button (primary action) - disabled when paused
                    Button {
                        AudioManager.shared.triggerHapticFeedback(.medium)
                        if timerManager.isBreak {
                            timerManager.switchToWork()
                        } else {
                            timerManager.switchToBreak()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: timerManager.isBreak ? "briefcase.fill" : "cup.and.saucer.fill")
                                .font(.caption)

                            Text(timerManager.isBreak ? "Work" : "Break")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(timerManager.isBreak ? lastWorkCategoryColor : .red)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPaused)
                    .opacity(isPaused ? 0.5 : 1)

                    // Pause/Resume button - uses category color so you see what you're pausing
                    Button {
                        AudioManager.shared.triggerHapticFeedback(.medium)
                        if isPaused {
                            timerManager.resumeTimer()
                        } else {
                            timerManager.pauseTimer()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.caption)
                            Text(isPaused ? "Resume" : "Pause")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(pauseButtonColor.opacity(isPaused ? 1 : 0.7))
                        )
                    }
                    .buttonStyle(.plain)

                    // Stop button - does NOT mark complete (preserves partial fill)
                    Button {
                        AudioManager.shared.triggerHapticFeedback(.medium)
                        timerManager.stopTimer(markComplete: false)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.caption)
                            Text("Stop")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)  // Match grid and sticky bar padding
            .background(Color(.systemBackground))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: shouldShow)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        FloatingTimerBar()
            .padding(.bottom, 60)
    }
    .environmentObject(TimerManager())
    .environmentObject(BlockManager())
}
