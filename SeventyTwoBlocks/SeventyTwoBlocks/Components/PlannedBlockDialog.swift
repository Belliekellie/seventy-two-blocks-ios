import SwiftUI

struct PlannedBlockDialog: View {
    let block: Block
    let onStart: () -> Void
    let onStartAsBreak: () -> Void
    let onSkip: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject var blockManager: BlockManager

    private var categoryColor: Color {
        guard let categoryId = block.category,
              let cat = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return .blue
        }
        return cat.swiftUIColor
    }

    private var categoryLabel: String {
        guard let categoryId = block.category,
              let cat = blockManager.categories.first(where: { $0.id == categoryId }) else {
            return "Planned"
        }
        return cat.label
    }

    private var blockTime: String {
        "\(Block.blockToTime(block.blockIndex)) - \(Block.blockEndTime(block.blockIndex))"
    }

    var body: some View {
        VStack(spacing: 24) {
            // Clock icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "clock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(categoryColor)
            }

            // Title
            VStack(spacing: 8) {
                Text("Planned Block Starting")
                    .font(.title2.bold())

                VStack(spacing: 4) {
                    Text(block.label ?? categoryLabel)
                        .font(.headline)
                        .foregroundStyle(categoryColor)

                    Text(blockTime)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Info
            if let note = block.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Action buttons
            VStack(spacing: 12) {
                // Primary action - Start
                Button(action: onStart) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Now")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(categoryColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Alternate action - Take Break Instead
                Button(action: onStartAsBreak) {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("Take Break Instead")
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

                // Secondary actions
                HStack(spacing: 12) {
                    Button(action: onSkip) {
                        HStack(spacing: 6) {
                            Image(systemName: "forward.fill")
                                .font(.caption)
                            Text("Skip Block")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.12))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
                        )
                    }

                    Button(action: onDismiss) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text("Later")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
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
            AudioManager.shared.playCompletionBell()
        }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.4)
            .ignoresSafeArea()

        PlannedBlockDialog(
            block: Block(
                id: UUID().uuidString,
                userId: "",
                date: "2024-01-01",
                blockIndex: 30,
                isMuted: false,
                isActivated: false,
                category: "work",
                label: "Build iOS App",
                note: "Focus on timer implementation",
                status: .planned,
                progress: 0,
                breakProgress: 0,
                runs: nil,
                activeRunSnapshot: nil,
                segments: [],
                usedSeconds: 0,
                createdAt: "",
                updatedAt: ""
            ),
            onStart: {},
            onStartAsBreak: {},
            onSkip: {},
            onDismiss: {}
        )
        .environmentObject(BlockManager())
    }
}
