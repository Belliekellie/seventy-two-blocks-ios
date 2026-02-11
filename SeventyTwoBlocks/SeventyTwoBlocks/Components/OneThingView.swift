import SwiftUI

/// Sticky component that displays:
/// 1. The main goal for the day (editable)
/// 2. List of supporting actions (collapsible, aligned with main goal)
struct OneThingView: View {
    @EnvironmentObject var goalManager: GoalManager
    @Binding var selectedDate: Date
    @State private var isEditing = false
    @State private var editText = ""
    @AppStorage("actionsExpanded") private var actionsExpanded = true
    @State private var isAddingAction = false
    @State private var newActionText = ""
    @FocusState private var isFocused: Bool
    @FocusState private var actionFieldFocused: Bool

    // Primary brand color (matches web app - lighter glowing turquoise)
    private let primaryColor = Color(hue: 187/360, saturation: 0.70, brightness: 0.75)

    // Width of the checkbox area for consistent alignment
    private let checkboxWidth: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row - aligned with checkbox
            HStack(spacing: 10) {
                // Spacer matching checkbox width for alignment
                Image(systemName: "target")
                    .font(.caption)
                    .foregroundStyle(primaryColor)
                    .frame(width: checkboxWidth)

                Text("Today's Main Goal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                // Edit button for the goal
                if let goal = goalManager.mainGoal, !goal.text.isEmpty, !isEditing {
                    Button {
                        editText = goal.text
                        isEditing = true
                        isFocused = true
                    } label: {
                        Text("Edit")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(primaryColor)
                    }
                }
            }

            // Main Goal
            if let goal = goalManager.mainGoal, !goal.text.isEmpty, !isEditing {
                // Display mode
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        goalManager.toggleMainGoalComplete()
                        AudioManager.shared.triggerHapticFeedback(.light)
                    } label: {
                        Image(systemName: goal.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(goal.isComplete ? .green : .secondary)
                            .frame(width: checkboxWidth)
                    }

                    Text(goal.text)
                        .font(.body.weight(.medium))
                        .strikethrough(goal.isComplete)
                        .foregroundStyle(goal.isComplete ? .secondary : .primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editText = goal.text
                            isEditing = true
                            isFocused = true
                        }
                }
            } else {
                // Edit/empty mode
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.4))
                        .frame(width: checkboxWidth)

                    if isEditing {
                        TextField("What's your #1 goal today?", text: $editText)
                            .font(.body)
                            .focused($isFocused)
                            .onSubmit { saveGoal() }

                        Button {
                            saveGoal()
                        } label: {
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
                    } else {
                        Text("Set your main goal...")
                            .font(.body)
                            .foregroundStyle(.secondary.opacity(0.6))
                            .onTapGesture {
                                isEditing = true
                                isFocused = true
                            }
                    }
                }
            }

            // Supporting Actions Section (always visible, collapsible)
            // Aligned with main goal checkbox
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        actionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        // Chevron in same column as checkbox
                        Image(systemName: actionsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: checkboxWidth)

                        Text("Supporting Actions")
                            .font(.caption2.weight(.medium).smallCaps())
                            .foregroundStyle(.secondary)

                        if !goalManager.actions.isEmpty {
                            Text("(\(goalManager.actions.filter { $0.isComplete }.count)/\(goalManager.actions.count))")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Add button - on the right
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAddingAction = true
                        actionsExpanded = true
                        actionFieldFocused = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(primaryColor)
                }
                .buttonStyle(.plain)
            }

            // Actions list (when expanded) - aligned with checkbox column
            if actionsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(goalManager.actions) { action in
                        ActionDisplayRow(action: action, checkboxWidth: checkboxWidth)
                    }

                    // Inline add action input
                    if isAddingAction {
                        HStack(spacing: 10) {
                            Image(systemName: "square")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.3))
                                .frame(width: checkboxWidth)

                            TextField("Add action...", text: $newActionText)
                                .font(.caption)
                                .focused($actionFieldFocused)
                                .onSubmit { addAction() }

                            if !newActionText.isEmpty {
                                Button {
                                    addAction()
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            // X button aligned with plus button above
                            Button {
                                isAddingAction = false
                                newActionText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func saveGoal() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            goalManager.setMainGoal(trimmed, for: selectedDate)
        } else {
            // User cleared the text - delete the goal
            goalManager.clearMainGoal(for: selectedDate)
        }
        isEditing = false
        isFocused = false
        editText = ""
    }

    private func addAction() {
        let trimmed = newActionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        goalManager.addAction(trimmed, for: selectedDate)
        newActionText = ""
        AudioManager.shared.triggerHapticFeedback(.light)
        // Keep input open and focused for adding more actions
        actionFieldFocused = true
    }
}

/// Display row for an action - smaller styling, aligned with main goal
struct ActionDisplayRow: View {
    let action: SupportingAction
    let checkboxWidth: CGFloat
    @EnvironmentObject var goalManager: GoalManager

    var body: some View {
        HStack(spacing: 10) {
            // Small checkbox - aligned with main goal checkbox
            Button {
                goalManager.toggleActionComplete(action)
                AudioManager.shared.triggerHapticFeedback(.light)
            } label: {
                Image(systemName: action.isComplete ? "checkmark.square.fill" : "square")
                    .font(.caption)
                    .foregroundStyle(action.isComplete ? .green : .secondary.opacity(0.5))
                    .frame(width: checkboxWidth)
            }

            // Action text - smaller than main goal
            Text(action.text)
                .font(.caption)
                .strikethrough(action.isComplete)
                .foregroundStyle(.secondary)
                .opacity(action.isComplete ? 0.6 : 1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            // Delete button - subtle
            Button {
                goalManager.deleteAction(action)
                AudioManager.shared.triggerHapticFeedback(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - InlineAddActionBar (Inside the sticky OneThingView)

/// Compact input for adding actions - fits inside the OneThingView card
struct InlineAddActionBar: View {
    @EnvironmentObject var goalManager: GoalManager
    @Binding var selectedDate: Date
    @State private var newActionText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.5))

            TextField("Add action...", text: $newActionText)
                .font(.caption)
                .focused($isFocused)
                .onSubmit { addAction() }

            if !newActionText.isEmpty {
                Button {
                    addAction()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color(hue: 187/360, saturation: 0.70, brightness: 0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemBackground).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func addAction() {
        let trimmed = newActionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        goalManager.addAction(trimmed, for: selectedDate)
        newActionText = ""
        AudioManager.shared.triggerHapticFeedback(.light)
    }
}

// MARK: - AddActionBar (Legacy - in scrollable area)

/// Input bar for adding new supporting actions
/// Kept for backwards compatibility
struct AddActionBar: View {
    @EnvironmentObject var goalManager: GoalManager
    @Binding var selectedDate: Date
    @State private var newActionText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.6))

            TextField("Add supporting action...", text: $newActionText)
                .font(.caption)
                .focused($isFocused)
                .onSubmit { addAction() }

            if !newActionText.isEmpty {
                Button {
                    addAction()
                } label: {
                    Text("Add")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hue: 187/360, saturation: 0.70, brightness: 0.75))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func addAction() {
        let trimmed = newActionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        goalManager.addAction(trimmed, for: selectedDate)
        newActionText = ""
        AudioManager.shared.triggerHapticFeedback(.light)
    }
}

// Keep for backwards compatibility
struct SupportingActionsView: View {
    @EnvironmentObject var goalManager: GoalManager
    @Binding var selectedDate: Date

    var body: some View {
        AddActionBar(selectedDate: $selectedDate)
    }
}

#Preview {
    VStack(spacing: 16) {
        OneThingView(selectedDate: .constant(Date()))
        AddActionBar(selectedDate: .constant(Date()))
        Spacer()
    }
    .padding()
    .environmentObject(GoalManager())
}
