import SwiftUI

struct PausedExpiryDialog: View {
    let blockIndex: Int
    let onContinueWork: () -> Void
    let onTakeBreak: () -> Void
    let onStartNewBlock: () -> Void
    let onStop: () -> Void

    private var blockDisplayNumber: Int {
        // Convert to day-order display number (1-72)
        if blockIndex >= 24 && blockIndex <= 47 {
            return blockIndex - 24 + 1  // Morning: 1-24
        } else if blockIndex >= 48 && blockIndex <= 71 {
            return blockIndex - 48 + 25  // Afternoon: 25-48
        } else {
            return blockIndex + 49  // Night: 49-72
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Pause icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }

            // Title
            VStack(spacing: 8) {
                Text("Block Time Ended")
                    .font(.title2.bold())

                Text("Block \(blockDisplayNumber) finished while you were paused.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // No auto-continue message
            Text("Take your time \u{2014} no rush!")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .clipShape(Capsule())

            // Action buttons
            VStack(spacing: 12) {
                // Primary action - Continue working (on current block)
                Button(action: onContinueWork) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Continue Working")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Secondary action - Take a break
                Button(action: onTakeBreak) {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("Take a Break")
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

                // Tertiary actions - New Block and Stop
                HStack(spacing: 12) {
                    Button(action: onStartNewBlock) {
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

                    Button(action: onStop) {
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
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 24)
        .onAppear {
            AudioManager.shared.playAlertSound()
        }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        PausedExpiryDialog(
            blockIndex: 30,
            onContinueWork: {},
            onTakeBreak: {},
            onStartNewBlock: {},
            onStop: {}
        )
    }
}
