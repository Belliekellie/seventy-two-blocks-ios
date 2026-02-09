import SwiftUI

/// Compact combined view: Main goal on left, worked time + overview on right
struct CompactGoalStatsView: View {
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var blockManager: BlockManager
    @Binding var selectedDate: Date
    @Binding var showOverview: Bool

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isFocused: Bool

    private let primaryColor = Color(hue: 187/360, saturation: 0.70, brightness: 0.75)

    // Calculate worked time from segments (only .done blocks)
    private var totalWorkedSeconds: Int {
        return blockManager.blocks.reduce(0) { total, block in
            guard block.status == .done else { return total }
            let workSeconds = block.segments
                .filter { $0.type == .work }
                .reduce(0) { $0 + $1.seconds }
            // Round up to 20m if >= 19 minutes (autocontinue/completion)
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
        if totalWorkedSeconds > 0 && totalWorkedSeconds < 30 {
            return "<1m"
        }
        let totalMinutes = (totalWorkedSeconds + 30) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Left: Main Goal
            goalSection

            Spacer(minLength: 8)

            // Right: Worked + Overview
            statsSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Goal Section (Left)

    @ViewBuilder
    private var goalSection: some View {
        if isEditing {
            // Edit mode
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.caption)
                    .foregroundStyle(primaryColor)

                TextField("What's your #1 goal?", text: $editText)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit { saveGoal() }

                Button { saveGoal() } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button {
                    isEditing = false
                    editText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let goal = goalManager.mainGoal, !goal.text.isEmpty {
            // Display mode with goal
            HStack(spacing: 8) {
                Button {
                    goalManager.toggleMainGoalComplete()
                    AudioManager.shared.triggerHapticFeedback(.light)
                } label: {
                    Image(systemName: goal.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(goal.isComplete ? .green : .secondary)
                }

                Text(goal.text)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(goal.isComplete)
                    .foregroundStyle(goal.isComplete ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editText = goal.text
                        isEditing = true
                        isFocused = true
                    }
            }
        } else {
            // Empty state
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.caption)
                    .foregroundStyle(primaryColor.opacity(0.5))

                Text("Set today's goal...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary.opacity(0.6))
                    .onTapGesture {
                        isEditing = true
                        isFocused = true
                    }
            }
        }
    }

    // MARK: - Stats Section (Right)

    private var statsSection: some View {
        HStack(spacing: 12) {
            // Worked time
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(workedTimeString)
                    .font(.subheadline.weight(.semibold))
            }

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 20)

            // Overview button
            Button {
                showOverview = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("Overview")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func saveGoal() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            goalManager.setMainGoal(trimmed, for: selectedDate)
        }
        isEditing = false
        isFocused = false
        editText = ""
    }
}

#Preview {
    VStack {
        CompactGoalStatsView(selectedDate: .constant(Date()), showOverview: .constant(false))
            .padding()
        Spacer()
    }
    .environmentObject(GoalManager())
    .environmentObject(BlockManager())
}
