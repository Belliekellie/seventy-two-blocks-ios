import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget
//
// ALL countdown timers use Text(timerInterval:countsDown:true) which is OS-rendered
// and stops at 0:00 instead of counting up. This works even when the app is suspended.
//
// TimelineView is NOT used — it doesn't reliably fire in Live Activities when the
// app is backgrounded (confirmed by extensive testing across multiple git commits).
//
// The lock screen shows a 3-block timeline. Each block has its own progress bar,
// countdown, and auto-continue indicator. They activate sequentially — all OS-rendered,
// no app interaction needed. When Block 5 ends, its auto-continue starts counting.
// When that ends, Block 6's progress bar starts filling and its countdown starts.
// And so on through all 3 blocks.

struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen banner
            let state = context.state

            Group {
                if state.isAutoContinue {
                    // App pushed auto-continue state (foreground completion)
                    AutoContinueBannerView(context: context)
                } else {
                    // Autonomous 3-block timeline
                    BlockTimelineBannerView(context: context)
                }
            }
            .padding(16)
            .activityBackgroundTint(
                state.isAutoContinue
                    ? Color.green.opacity(0.15)
                    : (state.isBreak ? Color.red : Color.fromHSL(state.categoryColor)).opacity(0.15)
            )
        } dynamicIsland: { context in
            let state = context.state
            let blockColor = state.isBreak ? Color.red : Color.fromHSL(state.categoryColor)

            return DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    let blockNum = state.currentBlockDisplayNumber ?? context.attributes.blockDisplayNumber

                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLOCK \(blockNum)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))

                        if state.isAutoContinue {
                            Text("Continuing...")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.green)
                        } else {
                            Text("\(state.currentBlockStartTime ?? context.attributes.blockStartTime)-\(state.currentBlockEndTime ?? context.attributes.blockEndTime)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if state.isAutoContinue, let endAt = state.autoContinueEndAt {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(timerInterval: state.timerStartedAt...endAt, countsDown: true)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                            Text("AUTO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    } else {
                        // Current block countdown
                        Text(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: true)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    if state.isAutoContinue {
                        Text("Auto-continuing...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.green)
                    } else if let label = state.label ?? state.category {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(blockColor)
                                .frame(width: 8, height: 8)
                            Text(label)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if state.isAutoContinue {
                        Rectangle()
                            .fill(Color.green)
                            .frame(height: 4)
                            .cornerRadius(2)
                            .padding(.top, 4)
                    } else {
                        VStack(spacing: 4) {
                            // Current block progress
                            ProgressView(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: false)
                                .tint(blockColor)
                                .labelsHidden()

                            // Upcoming phases (compact)
                            HStack(spacing: 8) {
                                // Auto-continue
                                if let acEnd = state.autoContinueEndAt {
                                    HStack(spacing: 2) {
                                        Image(systemName: "forward.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.green)
                                        Text(timerInterval: state.timerEndAt...acEnd, countsDown: true)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .monospacedDigit()
                                            .foregroundStyle(.green)
                                    }

                                    // Upcoming blocks (show up to 3 in the compact DI row)
                                    if state.upcomingBlocks.indices.contains(0) {
                                        HStack(spacing: 2) {
                                            Text("B\(state.upcomingBlocks[0].displayNumber)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            Text(timerInterval: state.upcomingBlocks[0].timerStartAt...state.upcomingBlocks[0].timerEndAt, countsDown: true)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if state.upcomingBlocks.indices.contains(1) {
                                        HStack(spacing: 2) {
                                            Text("B\(state.upcomingBlocks[1].displayNumber)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            Text(timerInterval: state.upcomingBlocks[1].timerStartAt...state.upcomingBlocks[1].timerEndAt, countsDown: true)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if state.upcomingBlocks.indices.contains(2) {
                                        HStack(spacing: 2) {
                                            Text("B\(state.upcomingBlocks[2].displayNumber)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            Text(timerInterval: state.upcomingBlocks[2].timerStartAt...state.upcomingBlocks[2].timerEndAt, countsDown: true)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                if state.isAutoContinue {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else {
                    let blockNum = state.currentBlockDisplayNumber ?? context.attributes.blockDisplayNumber
                    let blockIdx = state.currentBlockIndex ?? context.attributes.blockIndex
                    VStack(alignment: .leading, spacing: 0) {
                        Text("B\(blockNum)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Text(BlockTimeUtils.compactBlockRange(blockIdx))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactTrailing: {
                if state.isAutoContinue, let endAt = state.autoContinueEndAt {
                    Text(timerInterval: state.timerStartedAt...endAt, countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                } else {
                    // Current block countdown only — shows this block's remaining time
                    Text(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: true)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            } minimal: {
                if state.isAutoContinue, let endAt = state.autoContinueEndAt {
                    Text(timerInterval: state.timerStartedAt...endAt, countsDown: true)
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                } else {
                    // Current block countdown only
                    Text(timerInterval: state.timerStartedAt...state.timerEndAt, countsDown: true)
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Block Phase Row (single block in the timeline)
// Shows: block number, progress bar, block countdown, auto-continue countdown

struct BlockPhaseRow: View {
    let blockNum: Int
    let blockStart: Date      // When this block's timer starts (for timerInterval)
    let blockEnd: Date        // When this block's timer ends
    let acEnd: Date?          // When auto-continue ends (nil = no auto-continue)
    let color: Color
    let isCurrentBlock: Bool  // First block gets emphasized styling

    var body: some View {
        HStack(spacing: 6) {
            // Block label
            Text("B\(blockNum)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(isCurrentBlock ? .primary : .secondary)
                .frame(width: 30, alignment: .leading)

            // Progress bar — fills during this block, empty before, full after
            ProgressView(timerInterval: blockStart...blockEnd, countsDown: false)
                .tint(isCurrentBlock ? color : color.opacity(0.6))
                .labelsHidden()

            // Block countdown — counts down during block, stops at 0:00
            Text(timerInterval: blockStart...blockEnd, countsDown: true)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isCurrentBlock ? .primary : .secondary)
                .frame(minWidth: 44, alignment: .trailing)

            // Auto-continue countdown — starts counting when block ends, stops at 0:00
            if let acEnd = acEnd, acEnd > blockEnd {
                Text(timerInterval: blockEnd...acEnd, countsDown: true)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .frame(minWidth: 30, alignment: .trailing)
            }
        }
    }
}

// MARK: - Block Timeline Banner View (lock screen — 3-block autonomous timeline)

struct BlockTimelineBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let state = context.state
        let blockColor = state.isBreak ? Color.red : Color.fromHSL(state.categoryColor)
        let blockNum = state.currentBlockDisplayNumber ?? context.attributes.blockDisplayNumber

        VStack(spacing: 8) {
            // Header: category/label
            HStack(spacing: 6) {
                Circle()
                    .fill(blockColor)
                    .frame(width: 10, height: 10)

                if let label = state.label ?? state.category {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                }

                if state.isBreak {
                    Text("BREAK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                }

                Spacer()

                Text("\(state.currentBlockStartTime ?? context.attributes.blockStartTime)-\(state.currentBlockEndTime ?? context.attributes.blockEndTime)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Block 1 (current)
            BlockPhaseRow(
                blockNum: blockNum,
                blockStart: state.timerStartedAt,
                blockEnd: state.timerEndAt,
                acEnd: state.autoContinueEndAt,
                color: blockColor,
                isCurrentBlock: true
            )

            // Upcoming block 1
            if state.upcomingBlocks.indices.contains(0) {
                BlockPhaseRow(
                    blockNum: state.upcomingBlocks[0].displayNumber,
                    blockStart: state.upcomingBlocks[0].timerStartAt,
                    blockEnd: state.upcomingBlocks[0].timerEndAt,
                    acEnd: state.upcomingBlocks[0].autoContinueEndAt,
                    color: blockColor,
                    isCurrentBlock: false
                )
            }

            // Upcoming block 2
            if state.upcomingBlocks.indices.contains(1) {
                BlockPhaseRow(
                    blockNum: state.upcomingBlocks[1].displayNumber,
                    blockStart: state.upcomingBlocks[1].timerStartAt,
                    blockEnd: state.upcomingBlocks[1].timerEndAt,
                    acEnd: state.upcomingBlocks[1].autoContinueEndAt,
                    color: blockColor,
                    isCurrentBlock: false
                )
            }

            // "+N more" indicator
            if state.upcomingBlocks.count > 2 {
                Text("+\(state.upcomingBlocks.count - 2) more block\(state.upcomingBlocks.count - 2 == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Auto-Continue Banner View (shown when app pushes isAutoContinue=true)

struct AutoContinueBannerView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let state = context.state
        let blockNum = state.currentBlockDisplayNumber ?? context.attributes.blockDisplayNumber

        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BLOCK \(blockNum)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))

                    Text(state.isBreak ? "Break Complete" : "Block Complete")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }

                Spacer()

                if let endAt = state.autoContinueEndAt {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: state.timerStartedAt...endAt, countsDown: true)
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

// MARK: - Check-In Banner View

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
