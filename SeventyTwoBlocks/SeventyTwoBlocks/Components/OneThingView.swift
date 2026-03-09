import SwiftUI

/// Compact sticky row showing the main goal for the day
struct OneThingView: View {
    @EnvironmentObject var goalManager: GoalManager
    @Binding var selectedDate: Date
    @State private var isEditing = false
    @State private var editText = ""
    @State private var originalText = ""
    @FocusState private var isFocused: Bool

    // Primary brand color
    private let primaryColor = Color(hue: 187/360, saturation: 0.70, brightness: 0.75)

    var body: some View {
        HStack(spacing: 8) {
            // Target icon — always in the same spot
            Button {
                if let goal = goalManager.mainGoal, !goal.text.isEmpty, !isEditing {
                    goalManager.toggleMainGoalComplete()
                    AudioManager.shared.triggerHapticFeedback(.light)
                }
            } label: {
                Image(systemName: (goalManager.mainGoal?.isComplete == true && !isEditing) ? "checkmark.circle.fill" : "target")
                    .font(.subheadline)
                    .foregroundStyle(
                        (goalManager.mainGoal?.isComplete == true && !isEditing)
                            ? .green
                            : (goalManager.mainGoal?.text.isEmpty ?? true) && !isEditing
                                ? primaryColor.opacity(0.4)
                                : primaryColor
                    )
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .allowsHitTesting(goalManager.mainGoal?.text.isEmpty == false && !isEditing)

            // "Today's Main Goal:" label — always in the same spot
            Text("Today's Main Goal:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary.opacity(
                    (goalManager.mainGoal?.text.isEmpty ?? true) && !isEditing ? 0.5 : 1.0
                ))
                .fixedSize()

            if let goal = goalManager.mainGoal, !goal.text.isEmpty, !isEditing {
                // Display mode: goal text in small caps
                Text(goal.text.uppercased())
                    .font(.caption.weight(.semibold))
                    .strikethrough(goal.isComplete)
                    .foregroundStyle(goal.isComplete ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editText = goal.text
                        originalText = goal.text
                        isEditing = true
                        isFocused = true
                    }

                // X to clear
                Button {
                    goalManager.clearMainGoal(for: selectedDate)
                    AudioManager.shared.triggerHapticFeedback(.light)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if isEditing {
                // Edit mode
                TextField("Type your goal...", text: $editText)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit { saveGoal() }

                if !editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        saveGoal()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // X clears text AND exits edit, clearing any existing goal too
                Button {
                    // If there was an existing goal, clear it from storage
                    if !originalText.isEmpty {
                        goalManager.clearMainGoal(for: selectedDate)
                    }
                    editText = ""
                    isEditing = false
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary.opacity(0.5))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Empty state — tap anywhere
                Text("Set your goal...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary.opacity(0.4))

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                if let goal = goalManager.mainGoal, !goal.text.isEmpty {
                    // Has a goal — tapping enters edit mode
                    editText = goal.text
                    originalText = goal.text
                    isEditing = true
                    isFocused = true
                } else {
                    // No goal — tapping enters edit mode
                    originalText = ""
                    editText = ""
                    isEditing = true
                    isFocused = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func saveGoal() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            goalManager.setMainGoal(trimmed, for: selectedDate)
        } else {
            goalManager.clearMainGoal(for: selectedDate)
        }
        isEditing = false
        isFocused = false
        editText = ""
    }
}

#Preview {
    VStack(spacing: 16) {
        OneThingView(selectedDate: .constant(Date()))
        Spacer()
    }
    .padding()
    .environmentObject(GoalManager())
}
