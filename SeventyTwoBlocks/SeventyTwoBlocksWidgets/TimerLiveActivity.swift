import ActivityKit
import WidgetKit
import SwiftUI

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen banner view
            // Use TimelineView to re-evaluate at key transition times
            // Include Date() to ensure correct rendering for current state (not just future dates)
            TimelineView(.explicit([
                Date(),
                context.state.timerEndAt,
                context.state.autoContinueEndAt,
                context.state.nextBlockTimerEndAt,
                context.state.nextBlockAutoContinueEndAt
            ].compactMap { $0 })) { timeline in
                let now = timeline.date
                let state = context.state

                // Determine which phase we're in
                let currentBlockExpired = now >= state.timerEndAt
                let autoContinueExpired = state.autoContinueEndAt.map { now >= $0 } ?? false
                let nextBlockExpired = state.nextBlockTimerEndAt.map { now >= $0 } ?? false
                let nextAutoContinueExpired = state.nextBlockAutoContinueEndAt.map { now >= $0 } ?? false

                if !currentBlockExpired {
                    // Phase 1: Current block running
                    LockScreenBannerView(context: context)
                        .padding(16)
                        .activityBackgroundTint((state.isBreak ? Color.red : Color.fromHSL(state.categoryColor)).opacity(0.15))
                } else if !autoContinueExpired {
                    // Phase 2: Auto-continue countdown
                    AutoContinueBannerView(context: context, timerExpired: true)
                        .padding(16)
                        .activityBackgroundTint(Color.green.opacity(0.15))
                } else if let nextBlockEnd = state.nextBlockTimerEndAt, !nextBlockExpired {
                    // Phase 3: Next block running
                    NextBlockBannerView(context: context, nextBlockEndAt: nextBlockEnd)
                        .padding(16)
                        .activityBackgroundTint(Color.fromHSL(state.categoryColor).opacity(0.15))
                } else if let nextAutoEnd = state.nextBlockAutoContinueEndAt, !nextAutoContinueExpired {
                    // Phase 4: Next block's auto-continue countdown
                    NextBlockAutoContinueBannerView(context: context, autoContinueEndAt: nextAutoEnd)
                        .padding(16)
                        .activityBackgroundTint(Color.green.opacity(0.15))
                } else {
                    // Phase 5: All expired - show completion
                    AutoContinueBannerView(context: context, timerExpired: true)
                        .padding(16)
                        .activityBackgroundTint(Color.green.opacity(0.15))
                }
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

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let nextNum = context.state.nextBlockDisplayNumber {
                        Text("BLOCK \(nextNum)")
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

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let nextNum = context.state.nextBlockDisplayNumber {
                        Text("BLOCK \(nextNum)")
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
