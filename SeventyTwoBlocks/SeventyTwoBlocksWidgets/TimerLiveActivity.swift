import ActivityKit
import WidgetKit
import SwiftUI

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen banner view
            if context.state.isAutoContinue {
                AutoContinueBannerView(context: context)
                    .padding(16)
                    .activityBackgroundTint(Color.green.opacity(0.15))
            } else {
                LockScreenBannerView(context: context)
                    .padding(16)
                    .activityBackgroundTint((context.state.isBreak ? Color.red : Color.fromHSL(context.state.categoryColor)).opacity(0.15))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
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
                    if context.state.isAutoContinue, let endAt = context.state.autoContinueEndAt {
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

                DynamicIslandExpandedRegion(.center) {
                    if context.state.isAutoContinue {
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

                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.isAutoContinue {
                        // Animated progress bar
                        ProgressView(timerInterval: context.state.timerStartedAt...context.state.timerEndAt, countsDown: false)
                            .tint(context.state.isBreak ? .red : Color.fromHSL(context.state.categoryColor))
                            .labelsHidden()
                            .padding(.top, 4)
                    }
                }
            } compactLeading: {
                if context.state.isAutoContinue {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else {
                    Text("#B\(context.attributes.blockDisplayNumber)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
            } compactTrailing: {
                if context.state.isAutoContinue, let endAt = context.state.autoContinueEndAt {
                    Text(endAt, style: .timer)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                } else {
                    Text(context.state.timerEndAt, style: .timer)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            } minimal: {
                if context.state.isAutoContinue, let endAt = context.state.autoContinueEndAt {
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
