import SwiftUI

struct TimerCompleteDialog: View {
    let blockIndex: Int
    let category: String?
    let label: String?
    let totalDoneBlocks: Int  // For set celebration calculation
    let timerEndedAt: Date    // When the timer actually completed (for epoch-based countdown)
    let onContinue: () -> Void
    let onTakeBreak: () -> Void
    let onStartNewBlock: () -> Void
    let onSkipNextBlock: (() -> Void)?  // Optional: Skip the next block and continue to the one after
    let onStop: () -> Void

    @EnvironmentObject var blockManager: BlockManager
    @State private var countdown: Int = 25
    @State private var autoContinueTimer: Timer?
    @State private var showCelebration = false
    @AppStorage("disableAutoContinue") private var disableAutoContinue = false

    private let DAILY_WIN_BLOCKS = 12

    private var justCompletedSet: Bool {
        totalDoneBlocks > 0 && totalDoneBlocks % DAILY_WIN_BLOCKS == 0
    }

    private var setsCompleted: Int {
        totalDoneBlocks / DAILY_WIN_BLOCKS
    }

    private var categoryColor: Color {
        guard let categoryId = category,
              let cat = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return .green
        }
        return cat.swiftUIColor
    }

    private var categoryLabel: String {
        guard let categoryId = category,
              let cat = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return "Work"
        }
        return cat.label
    }

    private func ordinal(_ num: Int) -> String {
        let suffixes = ["st", "nd", "rd"]
        if num >= 1 && num <= 3 {
            return "\(num)\(suffixes[num - 1])"
        }
        return "\(num)th"
    }

    var body: some View {
        if showCelebration {
            celebrationView
        } else {
            regularCompletionView
        }
    }

    // MARK: - Celebration View (Set Complete)

    private var celebrationView: some View {
        VStack(spacing: 24) {
            // Trophy icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(categoryColor)
            }

            // Title
            VStack(spacing: 8) {
                Text("\(ordinal(setsCompleted)) Set Complete!")
                    .font(.title2.bold())

                Text("Amazing! You've completed \(setsCompleted * DAILY_WIN_BLOCKS) blocks today!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Auto-continue countdown
            if !disableAutoContinue && countdown > 0 {
                Text("Continuing in \(countdown)s...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Action buttons (same as regular completion)
            actionButtons
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 24)
        .onAppear {
            if !disableAutoContinue {
                startCountdown()
            }
            AudioManager.shared.playCompletionBell()
        }
        .onDisappear {
            stopCountdown()
        }
    }

    // MARK: - Regular Completion View

    private var regularCompletionView: some View {
        VStack(spacing: 24) {
            // Success icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(categoryColor)
            }

            // Title
            VStack(spacing: 8) {
                Text("Block Complete!")
                    .font(.title2.bold())

                Text("Great work on \(label ?? categoryLabel)!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Auto-continue countdown
            if !disableAutoContinue && countdown > 0 {
                Text("Continuing in \(countdown)s...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Action buttons
            actionButtons
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 24)
        .onAppear {
            // Check if we should show celebration
            if justCompletedSet {
                showCelebration = true
            }
            if !disableAutoContinue {
                startCountdown()
            }
            AudioManager.shared.playCompletionBell()
        }
        .onDisappear {
            stopCountdown()
        }
    }

    // MARK: - Action Buttons (shared)

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Primary action - Continue
            Button(action: {
                stopCountdown()
                onContinue()
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Continue Working")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(categoryColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Secondary action - Take break
            Button(action: {
                stopCountdown()
                onTakeBreak()
            }) {
                HStack {
                    Image(systemName: "cup.and.saucer.fill")
                    Text("Take a 5-min Break")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                )
            }

            // Tertiary actions - still visible but less prominent
            HStack(spacing: 12) {
                Button(action: {
                    stopCountdown()
                    onStartNewBlock()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.caption)
                        Text("New Block")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue.opacity(0.25), lineWidth: 1)
                    )
                }

                Button(action: {
                    stopCountdown()
                    onStop()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                        Text("I'm Done")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.12))
                    .foregroundStyle(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.purple.opacity(0.25), lineWidth: 1)
                    )
                }
            }

            // Skip next block option (if provided)
            if let skipAction = onSkipNextBlock {
                Button(action: {
                    stopCountdown()
                    skipAction()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.end.fill")
                            .font(.caption2)
                        Text("Skip Next Block")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func startCountdown() {
        // Epoch-based countdown: survives app backgrounding
        let elapsed = Int(Date().timeIntervalSince(timerEndedAt))
        countdown = max(0, 25 - elapsed)
        if countdown <= 0 {
            onContinue()
            return
        }
        autoContinueTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let elapsed = Int(Date().timeIntervalSince(timerEndedAt))
            let remaining = max(0, 25 - elapsed)
            countdown = remaining
            if remaining <= 0 {
                stopCountdown()
                onContinue()
            }
        }
    }

    private func stopCountdown() {
        autoContinueTimer?.invalidate()
        autoContinueTimer = nil
    }
}

#Preview("Regular Completion") {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        TimerCompleteDialog(
            blockIndex: 30,
            category: "work",
            label: "Building iOS App",
            totalDoneBlocks: 5,
            timerEndedAt: Date(),
            onContinue: {},
            onTakeBreak: {},
            onStartNewBlock: {},
            onSkipNextBlock: {},
            onStop: {}
        )
        .environmentObject(BlockManager())
    }
}

#Preview("Set Celebration") {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        TimerCompleteDialog(
            blockIndex: 30,
            category: "work",
            label: "Building iOS App",
            totalDoneBlocks: 12,  // Triggers celebration
            timerEndedAt: Date(),
            onContinue: {},
            onTakeBreak: {},
            onStartNewBlock: {},
            onSkipNextBlock: nil,
            onStop: {}
        )
        .environmentObject(BlockManager())
    }
}
