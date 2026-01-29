import WidgetKit
import SwiftUI

// MARK: - Circular Lock Screen Widget (Progress Gauge)

struct LockScreenCircularProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        completion(LockScreenEntry(date: Date(), data: WidgetDataReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
        let data = WidgetDataReader.read()
        let entry = LockScreenEntry(date: Date(), data: data)

        let currentIndex = BlockTimeUtils.getCurrentBlockIndex()
        let nextBlockDate = BlockTimeUtils.blockStartDate(for: min(currentIndex + 1, 71))
        let timeline = Timeline(entries: [entry], policy: .after(nextBlockDate))
        completion(timeline)
    }
}

struct LockScreenEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct LockScreenCircularWidget: Widget {
    let kind = "LockScreenCircularWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenCircularProvider()) { entry in
            LockScreenCircularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Block Progress")
        .description("Shows day progress or timer progress as a gauge.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenCircularView: View {
    let entry: LockScreenEntry

    private var progress: Double {
        if entry.data.timerActive, let initialTime = entry.data.timerInitialTime, initialTime > 0,
           let endAt = entry.data.timerEndAt {
            let remaining = endAt.timeIntervalSinceNow
            return max(0, min(1, 1.0 - remaining / Double(initialTime)))
        }
        return BlockTimeUtils.dayProgress(
            completed: entry.data.blocksCompletedToday,
            total: entry.data.totalActiveBlocks
        )
    }

    var body: some View {
        Gauge(value: progress) {
            if entry.data.timerActive {
                Image(systemName: entry.data.timerIsBreak ? "cup.and.saucer.fill" : "timer")
            } else {
                Text("\(entry.data.blocksCompletedToday)")
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Rectangular Lock Screen Widget (Block Info)

struct LockScreenRectangularProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        completion(LockScreenEntry(date: Date(), data: WidgetDataReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
        let data = WidgetDataReader.read()
        let entry = LockScreenEntry(date: Date(), data: data)

        let currentIndex = BlockTimeUtils.getCurrentBlockIndex()
        let nextBlockDate = BlockTimeUtils.blockStartDate(for: min(currentIndex + 1, 71))
        let timeline = Timeline(entries: [entry], policy: .after(nextBlockDate))
        completion(timeline)
    }
}

struct LockScreenRectangularWidget: Widget {
    let kind = "LockScreenRectangularWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenRectangularProvider()) { entry in
            LockScreenRectangularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Block Info")
        .description("Shows current block number, time range, and timer countdown.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenRectangularView: View {
    let entry: LockScreenEntry

    private var blockIndex: Int { entry.data.currentBlockIndex }
    private var displayNumber: Int { BlockTimeUtils.displayBlockNumber(blockIndex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("BLOCK \(displayNumber)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))

                Text("\(BlockTimeUtils.blockToTime(blockIndex))-\(BlockTimeUtils.blockEndTime(blockIndex))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if entry.data.timerActive, let endAt = entry.data.timerEndAt {
                HStack(spacing: 4) {
                    Image(systemName: entry.data.timerIsBreak ? "cup.and.saucer.fill" : "timer")
                        .font(.system(size: 10))
                    if let label = entry.data.timerLabel ?? entry.data.timerCategory {
                        Text(label)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(endAt, style: .timer)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(entry.data.blocksCompletedToday) blocks done")
                        .font(.system(size: 11))
                }
            }
        }
    }
}

#Preview(as: .accessoryCircular) {
    LockScreenCircularWidget()
} timeline: {
    LockScreenEntry(date: Date(), data: .empty)
}

#Preview(as: .accessoryRectangular) {
    LockScreenRectangularWidget()
} timeline: {
    LockScreenEntry(date: Date(), data: .empty)
}
