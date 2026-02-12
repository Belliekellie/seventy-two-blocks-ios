import SwiftUI

struct QuickActionsView: View {
    @EnvironmentObject var blockManager: BlockManager
    @EnvironmentObject var timerManager: TimerManager
    @State private var showResetConfirmation = false

    // Get custom segment name from settings
    @AppStorage("segmentNameNight") private var segmentNameNight = "Night"

    private var hasActiveTimer: Bool {
        timerManager.isActive
    }

    private var currentBlockIndex: Int {
        Block.getCurrentBlockIndex()
    }

    // Night/sleep blocks are blocks BEFORE the user's day start hour
    @AppStorage("dayStartHour") private var dayStartHour: Int = 6

    private var dayStartBlockIndex: Int {
        dayStartHour * 3  // 3 blocks per hour
    }

    private var nightBlocks: [Block] {
        blockManager.blocks.filter { $0.blockIndex < dayStartBlockIndex }
    }

    // Check if night blocks are currently activated (unmuted)
    // Night blocks are activated when they're NOT muted
    private var nightBlocksActivated: Bool {
        // At least one night block is unmuted (activated)
        nightBlocks.contains { !$0.isMuted }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Night Mode Toggle
            Button {
                toggleNightBlocks()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: nightBlocksActivated ? "moon.fill" : "moon")
                        .font(.caption)
                    Text(nightBlocksActivated ? "Deactivate \(segmentNameNight) Blocks" : "Activate \(segmentNameNight) Blocks")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(nightBlocksActivated ? .white : .indigo)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(nightBlocksActivated ? Color.indigo : Color.indigo.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            // Reset Day
            Button {
                if !hasActiveTimer {
                    showResetConfirmation = true
                } else {
                    AudioManager.shared.triggerHapticFeedback(.error)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                    Text("Reset Day")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .alert("Reset All Blocks?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Day", role: .destructive) {
                resetAllBlocks()
            }
        } message: {
            Text("This will clear all data from today's blocks including categories, labels, and progress. This cannot be undone.")
        }
    }

    private func toggleNightBlocks() {
        Task {
            if nightBlocksActivated {
                // Deactivate: mute blocks that haven't been used
                // Don't touch blocks that are done or have recorded data
                for block in nightBlocks {
                    // Skip blocks that are done (preserve completed work)
                    if block.status == .done {
                        continue
                    }
                    // Skip blocks that have recorded data
                    if !block.segments.isEmpty || block.progress > 0 || block.usedSeconds > 0 {
                        continue
                    }

                    // Mute and reset to idle (handles both idle and incorrectly-skipped blocks)
                    var updatedBlock = block
                    updatedBlock.isMuted = true
                    updatedBlock.isActivated = false
                    updatedBlock.status = .idle
                    await blockManager.saveBlock(updatedBlock)
                }
            } else {
                // Activate: unmute all night blocks so they can be used
                // Also reset skipped blocks without data back to idle
                for block in nightBlocks {
                    if block.isMuted {
                        var updatedBlock = block
                        updatedBlock.isMuted = false
                        updatedBlock.isActivated = true
                        // Reset skipped blocks without data back to idle when activating
                        if block.status == .skipped {
                            let hasData = !block.segments.isEmpty || block.progress > 0 || block.usedSeconds > 0
                            if !hasData {
                                updatedBlock.status = .idle
                            }
                        }
                        await blockManager.saveBlock(updatedBlock)
                    }
                }
            }
            await blockManager.reloadBlocks()
            AudioManager.shared.triggerHapticFeedback(.medium)
        }
    }

    private func resetAllBlocks() {
        Task {
            await blockManager.resetTodayBlocks()
            AudioManager.shared.triggerHapticFeedback(.success)
        }
    }
}

#Preview {
    QuickActionsView()
        .padding()
        .environmentObject(BlockManager())
        .environmentObject(TimerManager())
}
