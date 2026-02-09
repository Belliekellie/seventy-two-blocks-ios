import SwiftUI

struct StatsCardView: View {
    @EnvironmentObject var blockManager: BlockManager
    @Binding var showOverview: Bool

    private var doneBlocks: Int {
        blockManager.blocks.filter { $0.status == .done }.count
    }

    // Calculate worked time from segments (matches web app)
    // Only counts actual work segments, not breaks
    // IMPORTANT: Only counts blocks that are .done - skipped blocks should not count toward totals
    private var totalWorkedSeconds: Int {
        return blockManager.blocks.reduce(0) { total, block in
            // Skip blocks that aren't done - skipped blocks shouldn't count toward worked time
            guard block.status == .done else { return total }

            // Sum work segments only
            let workSeconds = block.segments
                .filter { $0.type == .work }
                .reduce(0) { $0 + $1.seconds }

            // Round up to 20m (1200s) if worked >= 19 minutes
            // This credits autocontinue blocks that ran to completion
            if workSeconds >= 19 * 60 {
                return total + 20 * 60
            }
            return total + workSeconds
        }
    }

    private var workedTimeString: String {
        if totalWorkedSeconds == 0 {
            return "0m"
        }

        // Under 30 seconds shows as "<1m"
        if totalWorkedSeconds > 0 && totalWorkedSeconds < 30 {
            return "<1m"
        }

        // Round to nearest minute (30s+ rounds up)
        let totalMinutes = (totalWorkedSeconds + 30) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // Progress toward a "set" of 12 blocks
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
            // Breaks count
            StatItem(
                icon: "cup.and.saucer.fill",
                iconColor: .red,
                value: "\(breakBlocks)",
                label: "Breaks"
            )

            Divider()
                .frame(height: 40)

            // Worked time
            StatItem(
                icon: "clock.fill",
                iconColor: .blue,
                value: workedTimeString,
                label: "Worked"
            )

            Divider()
                .frame(height: 40)

            // Overview button
            Button(action: {
                showOverview = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    Text("Overview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatItem: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(iconColor)
                if !value.isEmpty {
                    Text(value)
                        .font(.title3.weight(.semibold))
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    StatsCardView(showOverview: .constant(false))
        .padding()
        .environmentObject(BlockManager())
}
