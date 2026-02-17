import SwiftUI

/// Overlay shown during check-in grace period.
/// The timer is running in the background - if the user doesn't respond,
/// the block will be marked as skipped when the timer completes.
struct CheckInGracePeriodView: View {
    let blockIndex: Int
    let timeLeft: Int
    let category: String?
    let label: String?
    let isBreakMode: Bool
    let onContinue: () -> Void
    let onTakeBreak: () -> Void
    let onBackToWork: () -> Void
    let onStop: () -> Void

    @EnvironmentObject var blockManager: BlockManager

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

    private var timeLeftText: String {
        let minutes = timeLeft / 60
        let seconds = timeLeft % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Warning icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }

            // Title and message
            VStack(spacing: 8) {
                Text("Still There?")
                    .font(.title2.bold())

                Text("You've completed several blocks without interaction. This is your grace period to confirm you're still working.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Countdown
            VStack(spacing: 4) {
                Text("Block ends in")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(timeLeftText)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Warning message
            Text("If you don't respond, this block will be skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()

            // Action buttons
            VStack(spacing: 12) {
                // Primary action - Continue in current mode
                Button(action: {
                    if isBreakMode {
                        onContinue()
                    } else {
                        onContinue()
                    }
                }) {
                    HStack {
                        Image(systemName: isBreakMode ? "moon.zzz.fill" : "play.fill")
                        Text(isBreakMode ? "Keep Resting" : "Continue Working")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isBreakMode ? Color.red : categoryColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Secondary action - Switch mode
                Button(action: {
                    if isBreakMode {
                        onBackToWork()
                    } else {
                        onTakeBreak()
                    }
                }) {
                    HStack {
                        Image(systemName: isBreakMode ? "play.fill" : "cup.and.saucer.fill")
                        Text(isBreakMode ? "Back to Work" : "Take a Break")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isBreakMode ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundStyle(isBreakMode ? .green : .red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder((isBreakMode ? Color.green : Color.red).opacity(0.3), lineWidth: 1)
                    )
                }

                // Stop button
                Button(action: onStop) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle")
                            .font(.caption)
                        Text("Stop Working")
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
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 24)
    }
}

#Preview("Check-In Grace Period - Work") {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        CheckInGracePeriodView(
            blockIndex: 30,
            timeLeft: 720,
            category: "work",
            label: "Building iOS App",
            isBreakMode: false,
            onContinue: {},
            onTakeBreak: {},
            onBackToWork: {},
            onStop: {}
        )
        .environmentObject(BlockManager())
    }
}

#Preview("Check-In Grace Period - Break") {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        CheckInGracePeriodView(
            blockIndex: 30,
            timeLeft: 300,
            category: nil,
            label: nil,
            isBreakMode: true,
            onContinue: {},
            onTakeBreak: {},
            onBackToWork: {},
            onStop: {}
        )
        .environmentObject(BlockManager())
    }
}
