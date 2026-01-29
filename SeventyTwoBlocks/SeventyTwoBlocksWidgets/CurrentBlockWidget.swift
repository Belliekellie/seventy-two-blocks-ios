import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct CurrentBlockProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentBlockEntry {
        CurrentBlockEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentBlockEntry) -> Void) {
        completion(CurrentBlockEntry(date: Date(), data: WidgetDataReader.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentBlockEntry>) -> Void) {
        let data = WidgetDataReader.read()
        var entries: [CurrentBlockEntry] = [CurrentBlockEntry(date: Date(), data: data)]

        // If timer is active, add an entry for when it expires
        // This prevents the widget from showing a stale timer counting up
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
            entries.append(CurrentBlockEntry(date: endAt, data: expiredData))
        }

        // Refresh at next block boundary
        let currentIndex = BlockTimeUtils.getCurrentBlockIndex()
        let nextBlockDate = BlockTimeUtils.blockStartDate(for: min(currentIndex + 1, 71))
        let timeline = Timeline(entries: entries, policy: .after(nextBlockDate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct CurrentBlockEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Widget Definition

struct CurrentBlockWidget: Widget {
    let kind = "CurrentBlockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentBlockProvider()) { entry in
            CurrentBlockWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Current Block")
        .description("Shows your current 20-minute block with timer countdown.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Views

struct CurrentBlockWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CurrentBlockEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallCurrentBlockView(data: entry.data)
        case .systemMedium:
            MediumCurrentBlockView(data: entry.data)
        default:
            SmallCurrentBlockView(data: entry.data)
        }
    }
}

// MARK: - Small Widget

struct SmallCurrentBlockView: View {
    let data: WidgetData

    private var blockIndex: Int { data.currentBlockIndex }
    private var displayNumber: Int { BlockTimeUtils.displayBlockNumber(blockIndex) }
    private var categoryColor: Color { .fromHSL(currentCategoryColor) }

    private var currentCategoryColor: String? {
        if data.timerActive { return data.timerCategoryColor }
        return data.blockStatuses.first { $0.index == blockIndex }?.categoryColor
    }

    private var currentLabel: String? {
        if data.timerActive { return data.timerLabel }
        return data.blockStatuses.first { $0.index == blockIndex }?.label
    }

    private var currentCategory: String? {
        if data.timerActive { return data.timerCategory }
        return data.blockStatuses.first { $0.index == blockIndex }?.category
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Block number
            Text("BLOCK \(displayNumber)")
                .font(.system(size: 18, weight: .bold, design: .monospaced))

            // Time range
            Text("\(BlockTimeUtils.blockToTime(blockIndex))-\(BlockTimeUtils.blockEndTime(blockIndex))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            // Category/label
            if let label = currentLabel ?? currentCategory {
                HStack(spacing: 4) {
                    Circle()
                        .fill(categoryColor)
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }

            // Timer active state (only show if endAt is still in the future)
            if data.timerActive, let endAt = data.timerEndAt, let startedAt = data.timerStartedAt, endAt > Date() {
                // Animated progress bar (labels hidden - otherwise shows a second counter)
                ProgressView(timerInterval: startedAt...endAt, countsDown: false)
                    .tint(data.timerIsBreak ? .orange : categoryColor)
                    .labelsHidden()

                // Countdown
                HStack(spacing: 4) {
                    Image(systemName: data.timerIsBreak ? "cup.and.saucer.fill" : "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(data.timerIsBreak ? .orange : .blue)
                    Text(endAt, style: .timer)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                }
            } else {
                // Stats when no timer
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("\(data.blocksCompletedToday) done")
                        .font(.system(size: 12, weight: .medium))
                    if data.hoursWorked > 0 {
                        Text("\u{00B7}")
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1fh", data.hoursWorked))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                .padding(-12)
        )
    }
}

// MARK: - Medium Widget

struct MediumCurrentBlockView: View {
    let data: WidgetData

    private var blockIndex: Int { data.currentBlockIndex }
    private var displayNumber: Int { BlockTimeUtils.displayBlockNumber(blockIndex) }
    private var categoryColor: Color { .fromHSL(currentCategoryColor) }

    private var currentCategoryColor: String? {
        if data.timerActive { return data.timerCategoryColor }
        return data.blockStatuses.first { $0.index == blockIndex }?.categoryColor
    }

    private var currentLabel: String? {
        if data.timerActive { return data.timerLabel }
        return data.blockStatuses.first { $0.index == blockIndex }?.label
    }

    private var currentCategory: String? {
        if data.timerActive { return data.timerCategory }
        return data.blockStatuses.first { $0.index == blockIndex }?.category
    }

    private var dayProgress: Int {
        guard data.totalActiveBlocks > 0 else { return 0 }
        return Int(Double(data.blocksCompletedToday) / Double(data.totalActiveBlocks) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: block info + timer
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("BLOCK \(displayNumber)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if data.timerActive, let endAt = data.timerEndAt, endAt > Date() {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(endAt, style: .timer)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                        if data.timerIsBreak {
                            Text("BREAK")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(width: 95, alignment: .trailing)
                }
            }

            Spacer(minLength: 4)

            // Time range
            Text("\(BlockTimeUtils.blockToTime(blockIndex)) - \(BlockTimeUtils.blockEndTime(blockIndex))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            // Category + label
            HStack(spacing: 6) {
                if let cat = currentCategory {
                    Circle()
                        .fill(categoryColor)
                        .frame(width: 8, height: 8)
                    Text(cat)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                if currentCategory != nil && currentLabel != nil {
                    Text("\u{00B7}")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                if let lbl = currentLabel {
                    Text(lbl)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 6)

            // Progress bar
            if data.timerActive, let startedAt = data.timerStartedAt, let endAt = data.timerEndAt, endAt > Date() {
                ProgressView(timerInterval: startedAt...endAt, countsDown: false)
                    .tint(data.timerIsBreak ? .orange : categoryColor)
                    .labelsHidden()
            }

            Spacer(minLength: 0)

            // Stats — four columns spread across full width
            HStack(spacing: 0) {
                StatColumn(label: "Finished Blocks", value: "\(data.blocksCompletedToday)")
                StatColumn(label: "Hours Worked", value: String(format: "%.1fh", data.hoursWorked))
                StatColumn(label: "Breaks Taken", value: "\(data.breaksTaken)")
                StatColumn(label: "Day Progress", value: "\(dayProgress)%")
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                .padding(-12)
        )
    }
}

// MARK: - Stat Column

struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview(as: .systemSmall) {
    CurrentBlockWidget()
} timeline: {
    CurrentBlockEntry(date: Date(), data: .empty)
}

#Preview(as: .systemMedium) {
    CurrentBlockWidget()
} timeline: {
    CurrentBlockEntry(date: Date(), data: .empty)
}
