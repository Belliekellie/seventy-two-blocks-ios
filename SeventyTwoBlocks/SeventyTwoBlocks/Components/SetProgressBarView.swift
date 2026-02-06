import SwiftUI

struct SetProgressBarView: View {
    @EnvironmentObject var blockManager: BlockManager

    private var doneBlocks: Int {
        blockManager.blocks.filter { $0.status == .done }.count
    }

    private var currentSetProgress: Int {
        doneBlocks % 12
    }

    private var completedSets: Int {
        doneBlocks / 12
    }

    private var breakBlocks: Int {
        blockManager.blocks.filter { block in
            block.segments.contains { $0.type == .break }
        }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Completed Blocks")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("\(currentSetProgress)/12")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    if completedSets > 0 {
                        Text("• \(completedSets) set\(completedSets == 1 ? "" : "s") done")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [.green, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(currentSetProgress) / 12, height: 6)
                    }
                }
                .frame(height: 6)
            }

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 12)

            // Right: breaks
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("\(breakBlocks)")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Breaks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    SetProgressBarView()
        .padding()
        .environmentObject(BlockManager())
}
