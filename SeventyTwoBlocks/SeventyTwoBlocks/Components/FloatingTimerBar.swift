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

    // Progress as 0-1 fraction (timerManager.progress is 0-100)
    private var progressFraction: Double {
        timerManager.progress / 100.0
    }

    var body: some View {
        if timerManager.isActive {
            VStack(spacing: 10) {
                // Row 1: Timer info
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: timerManager.isBreak ? "cup.and.saucer.fill" : "clock.fill")
                        .font(.title3)
                        .foregroundStyle(timerManager.isBreak ? .red : categoryColor)

                    // Block/Break label
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timerManager.isBreak ? "Break" : "Block \(blockDisplayNumber)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(blockTimeRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Countdown timer
                    Text(timeString)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(timerManager.timeLeft < 60 ? .red : (timerManager.isBreak ? .red : categoryColor))
                }

                // Row 2: Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(timerManager.isBreak ? Color.red : categoryColor)
                            .frame(width: max(0, geo.size.width * progressFraction), height: 6)
                    }
                }
                .frame(height: 6)

                // Row 3: Toggle button (full width)
                Button {
                    if timerManager.isBreak {
                        timerManager.switchToWork()
                    } else {
                        timerManager.switchToBreak()
                    }
                    AudioManager.shared.triggerHapticFeedback(.medium)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timerManager.isBreak ? "briefcase.fill" : "cup.and.saucer.fill")
                            .font(.caption)

                        Text(timerManager.isBreak ? "Back to work" : "5-min break")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(timerManager.isBreak ? .white : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(timerManager.isBreak ? categoryColor : .red)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)  // Match grid and sticky bar padding
            .background(Color(.systemBackground))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4), value: timerManager.isActive)
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
