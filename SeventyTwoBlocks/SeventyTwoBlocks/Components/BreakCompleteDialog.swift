import SwiftUI

struct BreakCompleteDialog: View {
    let blockIndex: Int
    let onContinueBreak: () -> Void
    let onBackToWork: () -> Void
    let onStartNewBlock: () -> Void
    let onStop: () -> Void

    @State private var countdown: Int = 30
    @State private var autoExtendTimer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            // Break icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
            }

            // Title
            VStack(spacing: 8) {
                Text("Break Complete")
                    .font(.title2.bold())

                Text("Feeling refreshed? Time to get back to work!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Auto-extend countdown
            if countdown > 0 {
                Text("Extending break in \(countdown)s...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Action buttons
            VStack(spacing: 12) {
                // Primary action - Back to work
                Button(action: {
                    stopCountdown()
                    onBackToWork()
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Back to Work")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Secondary action - Continue break
                Button(action: {
                    stopCountdown()
                    onContinueBreak()
                }) {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("Extend Break (+5 min)")
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
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .padding(.horizontal, 24)
        .onAppear {
            startCountdown()
            AudioManager.shared.playCompletionBell()
        }
        .onDisappear {
            stopCountdown()
        }
    }

    private func startCountdown() {
        countdown = 30
        autoExtendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                stopCountdown()
                onContinueBreak()
            }
        }
    }

    private func stopCountdown() {
        autoExtendTimer?.invalidate()
        autoExtendTimer = nil
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        BreakCompleteDialog(
            blockIndex: 30,
            onContinueBreak: {},
            onBackToWork: {},
            onStartNewBlock: {},
            onStop: {}
        )
    }
}
