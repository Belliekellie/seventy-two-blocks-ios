import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget
//
// KEY DESIGN: No phase switching. iOS does NOT reliably re-evaluate TimelineView
// in backgrounded Live Activities. Instead, ALL timers are always visible using
// Text(timerInterval:countsDown:true) which iOS updates automatically:
//   - Before the interval starts → shows full duration (static)
//   - During the interval → counts down
//   - After the interval ends → shows 0:00
// This means timers naturally "activate" in sequence without any code running.

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen banner — single view with stacked timers
            LockScreenBannerView(context: context)
                .padding(16)
                .activityBackgroundTint(
                    (context.state.isBreak ? Color.red : Color.fromHSL(context.state.categoryColor))
                        .opacity(0.15)
                )
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded - Leading (block info)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLOCK \((context.state.currentBlockDisplayNumber ?? context.attributes.blockDisplayNumber))")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                        Text("\(context.state.currentBlockStartTime ?? context.attributes.blockStartTime)-\(context.state.currentBlockEndTime ?? context.attributes.blockEndTime)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Expanded - Trailing (timer stack)
                DynamicIslandExpandedRegion(.trailing) {
                    let state = context.state
                    VStack(alignment: .trailing, spacing: 4) {
                        // Block countdown
                        Text(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: true)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .monospacedDigit()

                        // Auto-continue countdown (activates when block timer hits 0:00)
                        if let acEnd = state.autoContinueEndAt {
                            Text(timerInterval: state.timerEndAt...acEnd, countsDown: true)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }
                }

                // MARK: Expanded - Center (category label)
                DynamicIslandExpandedRegion(.center) {
                    if let label = context.state.label ?? context.state.category {
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

                // MARK: Expanded - Bottom (progress bar + next block)
                DynamicIslandExpandedRegion(.bottom) {
                    let state = context.state
                    VStack(spacing: 6) {
                        // Progress bar — fills during block, stays full after
                        ProgressView(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: false)
                            .tint(state.isBreak ? .red : Color.fromHSL(state.categoryColor))
                            .labelsHidden()

                        // Next block timer
                        if let acEnd = state.autoContinueEndAt,
                           let nextEnd = state.nextBlockTimerEndAt {
                            HStack {
                                if let nextNum = state.nextBlockDisplayNumber {
                                    Text("BLOCK \(nextNum)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(timerInterval: acEnd...nextEnd, countsDown: true)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

            // MARK: Compact Leading
            } compactLeading: {
                Text("#B\((context.state.currentBlockDisplayNumber ?? context.attributes.blockDisplayNumber))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))

            // MARK: Compact Trailing
            } compactTrailing: {
                // Block countdown — counts down to 0:00 then stays
                Text(timerInterval: context.state.timerStartedAt...context.state.timerEndAt, countsDown: true)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()

            // MARK: Minimal
            } minimal: {
                Text(timerInterval: context.state.timerStartedAt...context.state.timerEndAt, countsDown: true)
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Lock Screen Banner View

struct LockScreenBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let state = context.state

        VStack(spacing: 6) {
            // Top row: Block info + block countdown
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("BLOCK \((state.currentBlockDisplayNumber ?? context.attributes.blockDisplayNumber))")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))

                    HStack(spacing: 4) {
                        Text("\(state.currentBlockStartTime ?? context.attributes.blockStartTime)-\(state.currentBlockEndTime ?? context.attributes.blockEndTime)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if state.isBreak {
                            Text("BREAK")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                        }

                        if let label = state.label ?? state.category {
                            Circle()
                                .fill(Color.fromHSL(state.categoryColor))
                                .frame(width: 6, height: 6)
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Block countdown
                Text(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: true)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .monospacedDigit()
            }

            // Progress bar
            ProgressView(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: false)
                .tint(state.isBreak ? .red : Color.fromHSL(state.categoryColor))
                .labelsHidden()

            // Future timers — compact rows
            if let acEnd = state.autoContinueEndAt {
                // Row 1: Auto-continue + Next block on same line
                HStack(spacing: 0) {
                    // Auto-continue
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                        .frame(width: 14)
                    Text(timerInterval: state.timerEndAt...acEnd, countsDown: true)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.green)

                    if let nextEnd = state.nextBlockTimerEndAt,
                       let nextNum = state.nextBlockDisplayNumber {
                        Spacer()
                        Text("#\(nextNum)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(timerInterval: acEnd...nextEnd, countsDown: true)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                }

                // Row 2: Next auto-continue + Third block on same line
                if let nextEnd = state.nextBlockTimerEndAt,
                   let nextAcEnd = state.nextBlockAutoContinueEndAt {
                    HStack(spacing: 0) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.green.opacity(0.6))
                            .frame(width: 14)
                        Text(timerInterval: nextEnd...nextAcEnd, countsDown: true)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.green.opacity(0.6))

                        if let thirdEnd = state.thirdBlockTimerEndAt,
                           let thirdNum = state.thirdBlockDisplayNumber {
                            Spacer()
                            Text("#\(thirdNum)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text(timerInterval: nextAcEnd...thirdEnd, countsDown: true)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.secondary.opacity(0.6))
                                .padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }
}
