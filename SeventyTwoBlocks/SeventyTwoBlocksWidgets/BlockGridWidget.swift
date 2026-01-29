import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct BlockGridProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlockGridEntry {
        BlockGridEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (BlockGridEntry) -> Void) {
        completion(BlockGridEntry(date: Date(), data: WidgetDataReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlockGridEntry>) -> Void) {
        let data = WidgetDataReader.read()
        var entries: [BlockGridEntry] = [BlockGridEntry(date: Date(), data: data)]

        // If timer is active, add an entry for when it expires
        if data.timerActive, let endAt = data.timerEndAt, endAt > Date() {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: endAt)
            let minutesSinceStart = Int(endAt.timeIntervalSince(startOfDay)) / 60
            let blockIndexAtEnd = min(71, minutesSinceStart / WidgetConstants.blockDurationMinutes)

            let expiredData = WidgetData(
                currentBlockIndex: blockIndexAtEnd,
                blocksCompletedToday: data.blocksCompletedToday + (data.timerIsBreak ? 0 : 1),
                totalActiveBlocks: data.totalActiveBlocks,
                timerActive: false,
                timerIsBreak: false,
                timerEndAt: nil,
                timerStartedAt: nil,
                timerBlockIndex: nil,
                timerCategory: nil,
                timerCategoryColor: nil,
                timerLabel: nil,
                timerInitialTime: nil,
                blockStatuses: data.blockStatuses,
                mainGoalText: data.mainGoalText,
                mainGoalComplete: data.mainGoalComplete,
                hoursWorked: data.hoursWorked,
                breaksTaken: data.breaksTaken,
                lastUpdated: endAt
            )
            entries.append(BlockGridEntry(date: endAt, data: expiredData))
        }

        let currentIndex = BlockTimeUtils.getCurrentBlockIndex()
        let nextBlockDate = BlockTimeUtils.blockStartDate(for: min(currentIndex + 1, 71))
        let timeline = Timeline(entries: entries, policy: .after(nextBlockDate))
        completion(timeline)
    }
}

struct BlockGridEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Widget Definition

struct BlockGridWidget: Widget {
    let kind = "BlockGridWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BlockGridProvider()) { entry in
            BlockGridWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("72 Blocks Grid")
        .description("Overview of all 72 blocks for the day.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Grid View

struct BlockGridWidgetView: View {
    let entry: BlockGridEntry

    // Grid layout: 24 columns x 3 rows (Morning, Afternoon, Night)
    // Row 0: blocks 24-47 (Morning 08:00-16:00)
    // Row 1: blocks 48-71 (Afternoon 16:00-24:00)
    // Row 2: blocks 0-23  (Night 00:00-08:00)
    private let columns = 24
    private let rowRanges: [(label: String, range: ClosedRange<Int>)] = [
        ("AM", 24...47),
        ("PM", 48...71),
        ("NT", 0...23)
    ]

    private var currentBlockIndex: Int { entry.data.currentBlockIndex }
    private var statuses: [Int: WidgetBlockEntry] {
        Dictionary(uniqueKeysWithValues: entry.data.blockStatuses.map { ($0.index, $0) })
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("72 Blocks")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("\(entry.data.blocksCompletedToday)")
                        .font(.system(size: 13, weight: .semibold))
                }
            }

            // Timer info (if active)
            if entry.data.timerActive, let endAt = entry.data.timerEndAt, endAt > Date() {
                HStack(spacing: 6) {
                    Image(systemName: entry.data.timerIsBreak ? "cup.and.saucer.fill" : "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(entry.data.timerIsBreak ? .orange : .blue)

                    if let label = entry.data.timerLabel ?? entry.data.timerCategory {
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(endAt, style: .timer)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.fromHSL(entry.data.timerCategoryColor).opacity(0.15))
                )
            }

            // Grid
            VStack(spacing: 4) {
                ForEach(0..<rowRanges.count, id: \.self) { rowIdx in
                    let row = rowRanges[rowIdx]
                    VStack(spacing: 2) {
                        // Row label
                        HStack {
                            Text(row.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        // Block cells
                        HStack(spacing: 1.5) {
                            ForEach(Array(row.range), id: \.self) { blockIndex in
                                BlockCell(
                                    entry: statuses[blockIndex],
                                    isCurrent: blockIndex == currentBlockIndex,
                                    isTimerBlock: blockIndex == entry.data.timerBlockIndex && entry.data.timerActive
                                )
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Time labels
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if hour < 18 { Spacer() }
                }
            }
        }
    }
}

// MARK: - Individual Block Cell

struct BlockCell: View {
    let entry: WidgetBlockEntry?
    let isCurrent: Bool
    let isTimerBlock: Bool

    private var cellColor: Color {
        guard let entry = entry else { return .clear }

        switch entry.status {
        case .done:
            return .fromHSL(entry.categoryColor)
        case .active:
            return .fromHSL(entry.categoryColor).opacity(0.8)
        case .planned:
            return .fromHSL(entry.categoryColor).opacity(0.4)
        case .skipped:
            return Color.secondary.opacity(0.15)
        case .muted:
            return Color.secondary.opacity(0.08)
        case .idle:
            return Color.secondary.opacity(0.1)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(cellColor)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary, lineWidth: 1.5)
                }
            }
            .overlay {
                if isTimerBlock {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.blue, lineWidth: 1)
                }
            }
    }
}

#Preview(as: .systemLarge) {
    BlockGridWidget()
} timeline: {
    BlockGridEntry(date: Date(), data: .empty)
}
