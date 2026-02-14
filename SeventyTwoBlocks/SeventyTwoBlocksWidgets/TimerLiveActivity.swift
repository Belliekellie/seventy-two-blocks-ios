import ActivityKit
import WidgetKit
import SwiftUI

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen banner view
            // Use TimelineView to re-evaluate at key transition times
            // Include Date() to ensure correct rendering for current state (not just future dates)
            // Includes all 3 blocks to match check-in limit
            // Use periodic schedule that fires every second near transitions
            // .explicit() was NOT firing at scheduled times, causing the view to never update
            // .periodic() should force regular re-renders so phase detection works
            TimelineView(.periodic(from: Date(), by: 1.0)) { _ in
                // Use real current time for phase detection
                let realNow = Date()
                let state = context.state

                // Determine which phase we're in (6 phases for 3 blocks)
                // Use REAL current time for phase detection, not timeline.date
                let currentBlockExpired = realNow >= state.timerEndAt
                let autoContinueExpired = state.autoContinueEndAt.map { realNow >= $0 } ?? false
                let nextBlockExpired = state.nextBlockTimerEndAt.map { realNow >= $0 } ?? false
                let nextAutoContinueExpired = state.nextBlockAutoContinueEndAt.map { realNow >= $0 } ?? false
                let thirdBlockExpired = state.thirdBlockTimerEndAt.map { realNow >= $0 } ?? false
                let thirdAutoContinueExpired = state.thirdBlockAutoContinueEndAt.map { realNow >= $0 } ?? false

                // Calculate phase number for debug
                let phase: Int = {
                    if state.isAutoContinue && !autoContinueExpired { return 0 }
                    if !currentBlockExpired { return 1 }
                    if !autoContinueExpired { return 2 }
                    if state.nextBlockTimerEndAt != nil && !nextBlockExpired { return 3 }
                    if state.nextBlockAutoContinueEndAt != nil && !nextAutoContinueExpired { return 4 }
                    if state.thirdBlockTimerEndAt != nil && !thirdBlockExpired { return 5 }
                    if state.thirdBlockAutoContinueEndAt != nil && !thirdAutoContinueExpired { return 6 }
                    return 7
                }()

                // Calculate seconds until timerEndAt for debug
                let secsToEnd = Int(state.timerEndAt.timeIntervalSince(realNow))

                VStack(spacing: 4) {
                    // Debug info - show seconds to end (negative = past)
                    Text("P\(phase) \(secsToEnd)s exp:\(currentBlockExpired ? "Y" : "N")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Actual content based on phase
                    if state.isAutoContinue && !autoContinueExpired {
                        AutoContinueBannerView(context: context, timerExpired: true)
                    } else if !currentBlockExpired {
                        LockScreenBannerView(context: context)
                    } else if !autoContinueExpired {
                        AutoContinueBannerView(context: context, timerExpired: true)
                    } else if let nextBlockEnd = state.nextBlockTimerEndAt, !nextBlockExpired {
                        NextBlockBannerView(context: context, nextBlockEndAt: nextBlockEnd, blockNum: state.nextBlockDisplayNumber)
                    } else if let nextAutoEnd = state.nextBlockAutoContinueEndAt, !nextAutoContinueExpired {
                        NextBlockAutoContinueBannerView(context: context, autoContinueEndAt: nextAutoEnd, blockNum: state.nextBlockDisplayNumber)
                    } else if let thirdBlockEnd = state.thirdBlockTimerEndAt, !thirdBlockExpired {
                        NextBlockBannerView(context: context, nextBlockEndAt: thirdBlockEnd, blockNum: state.thirdBlockDisplayNumber)
                    } else if let thirdAutoEnd = state.thirdBlockAutoContinueEndAt, !thirdAutoContinueExpired {
                        NextBlockAutoContinueBannerView(context: context, autoContinueEndAt: thirdAutoEnd, blockNum: state.thirdBlockDisplayNumber)
                    } else {
                        CheckInBannerView(context: context)
                    }
                }
                .padding(16)
                .activityBackgroundTint({
                    if state.isAutoContinue && !autoContinueExpired { return Color.green.opacity(0.15) }
                    if !currentBlockExpired { return (state.isBreak ? Color.red : Color.fromHSL(state.categoryColor)).opacity(0.15) }
                    if !autoContinueExpired { return Color.green.opacity(0.15) }
                    if state.nextBlockTimerEndAt != nil && !nextBlockExpired { return Color.fromHSL(state.categoryColor).opacity(0.15) }
                    if state.nextBlockAutoContinueEndAt != nil && !nextAutoContinueExpired { return Color.green.opacity(0.15) }
                    if state.thirdBlockTimerEndAt != nil && !thirdBlockExpired { return Color.fromHSL(state.categoryColor).opacity(0.15) }
                    if state.thirdBlockAutoContinueEndAt != nil && !thirdAutoContinueExpired { return Color.green.opacity(0.15) }
                    return Color.orange.opacity(0.15)
                }())
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view - use TimelineView for smart switching
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLOCK \(context.attributes.blockDisplayNumber)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                        Text("\(context.attributes.blockStartTime)-\(context.attributes.blockEndTime)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.explicit([Date(), context.state.timerEndAt, context.state.autoContinueEndAt].compactMap { $0 })) { timeline in
                        let now = timeline.date
                        let timerExpired = now >= context.state.timerEndAt
                        let showAutoContinue = context.state.isAutoContinue || (timerExpired && context.state.autoContinueEndAt != nil)

                        if showAutoContinue, let endAt = context.state.autoContinueEndAt {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(endAt, style: .timer)
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                                Text("AUTO")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Text(context.state.timerEndAt, style: .timer)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    TimelineView(.explicit([Date(), context.state.timerEndAt])) { timeline in
                        let now = timeline.date
                        let timerExpired = now >= context.state.timerEndAt
                        let showAutoContinue = context.state.isAutoContinue || (timerExpired && context.state.autoContinueEndAt != nil)

                        if showAutoContinue {
                            Text("Continuing...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.green)
                        } else if let label = context.state.label ?? context.state.category {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.fromHSL(context.state.categoryColor))
                                    .frame(width: 8, height: 8)
                                Text(label)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.explicit([Date(), context.state.timerEndAt])) { timeline in
                        let now = timeline.date
                        let timerExpired = now >= context.state.timerEndAt
                        let showAutoContinue = context.state.isAutoContinue || (timerExpired && context.state.autoContinueEndAt != nil)

                        if !showAutoContinue {
                            // Animated progress bar
                            ProgressView(timerInterval: context.state.timerStartedAt...context.state.timerEndAt, countsDown: false)
                                .tint(context.state.isBreak ? .red : Color.fromHSL(context.state.categoryColor))
                                .labelsHidden()
                                .padding(.top, 4)
                        }
                    }
                }
            } compactLeading: {
                TimelineView(.explicit([Date(), context.state.timerEndAt])) { timeline in
                    let now = timeline.date
                    let timerExpired = now >= context.state.timerEndAt
                    let showAutoContinue = context.state.isAutoContinue || (timerExpired && context.state.autoContinueEndAt != nil)

                    if showAutoContinue {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    } else {
                        Text("#B\(context.attributes.blockDisplayNumber)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                }
            } compactTrailing: {
                TimelineView(.explicit([Date(), context.state.timerEndAt, context.state.autoContinueEndAt].compactMap { $0 })) { timeline in
                    let now = timeline.date
                    let timerExpired = now >= context.state.timerEndAt
                    let showAutoContinue = context.state.isAutoContinue || (timerExpired && context.state.autoContinueEndAt != nil)

                    if showAutoContinue, let endAt = context.state.autoContinueEndAt {
                        Text(endAt, style: .timer)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    } else {
                        Text(context.state.timerEndAt, style: .timer)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            } minimal: {
                TimelineView(.explicit([Date(), context.state.timerEndAt, context.state.autoContinueEndAt].compactMap { $0 })) { timeline in
                    let now = timeline.date
                    let timerExpired = now >= context.state.timerEndAt
                    let showAutoContinue = context.state.isAutoContinue || (timerExpired && context.state.autoContinueEndAt != nil)

                    if showAutoContinue, let endAt = context.state.autoContinueEndAt {
                        Text(endAt, style: .timer)
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    } else {
                        Text(context.state.timerEndAt, style: .timer)
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Lock Screen Banner View

struct LockScreenBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            // Top row: Block info + countdown
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BLOCK \(context.attributes.blockDisplayNumber)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))

                    Text("\(context.attributes.blockStartTime)-\(context.attributes.blockEndTime)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.timerEndAt, style: .timer)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .monospacedDigit()

                    if context.state.isBreak {
                        Text("BREAK")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
            }

            // Category/label
            if let label = context.state.label ?? context.state.category {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.fromHSL(context.state.categoryColor))
                        .frame(width: 10, height: 10)
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                }
            }

            // Animated progress bar
            ProgressView(timerInterval: context.state.timerStartedAt...context.state.timerEndAt, countsDown: false)
                .tint(context.state.isBreak ? .red : Color.fromHSL(context.state.categoryColor))
                .labelsHidden()
        }
    }
}

// MARK: - Auto-Continue Banner View

struct AutoContinueBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>
    var timerExpired: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BLOCK \(context.attributes.blockDisplayNumber)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))

                    Text(context.state.isBreak ? "Break Complete" : "Block Complete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }

                Spacer()

                if let endAt = context.state.autoContinueEndAt {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(endAt, style: .timer)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.green)

                        Text("AUTO-CONTINUE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }
}

// MARK: - Next Block Banner View

struct NextBlockBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>
    let nextBlockEndAt: Date
    var blockNum: Int? = nil  // Optional - uses nextBlockDisplayNumber if nil

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let num = blockNum ?? context.state.nextBlockDisplayNumber {
                        Text("BLOCK \(num)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    } else {
                        Text("NEXT BLOCK")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    }

                    Text("Auto-continued")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(nextBlockEndAt, style: .timer)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .monospacedDigit()
            }

            // Category/label from previous block
            if let label = context.state.label ?? context.state.category {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.fromHSL(context.state.categoryColor))
                        .frame(width: 10, height: 10)
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Next Block Auto-Continue Banner View

struct NextBlockAutoContinueBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>
    let autoContinueEndAt: Date
    var blockNum: Int? = nil  // Optional - uses nextBlockDisplayNumber if nil

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let num = blockNum ?? context.state.nextBlockDisplayNumber {
                        Text("BLOCK \(num)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    } else {
                        Text("BLOCK")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                    }

                    Text("Block Complete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(autoContinueEndAt, style: .timer)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.green)

                    Text("AUTO-CONTINUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

// MARK: - Check-In Banner View (shown when 3-block limit reached)

struct CheckInBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("STILL THERE?")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))

                    Text("3 blocks completed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)

                    Text("TAP TO CONTINUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
