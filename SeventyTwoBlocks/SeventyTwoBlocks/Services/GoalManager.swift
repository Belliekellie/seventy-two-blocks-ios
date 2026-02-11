import Foundation
import Combine

@MainActor
final class GoalManager: ObservableObject {
    @Published var mainGoal: MainGoal?
    @Published var actions: [SupportingAction] = []
    @Published var isLoading = false

    private var currentDate: String = ""

    // MARK: - Load Goals for Date

    func loadGoals(for date: Date) async {
        let dateString = formatDate(date)

        // Always update current date and reload
        currentDate = dateString
        isLoading = true
        defer { isLoading = false }

        // Clear existing data first
        mainGoal = nil
        actions = []

        // Try to load from UserDefaults (local storage for now)
        // In production, this would load from Supabase
        if let data = UserDefaults.standard.data(forKey: "mainGoal_\(dateString)"),
           let goal = try? JSONDecoder().decode(MainGoal.self, from: data) {
            mainGoal = goal
        }

        if let data = UserDefaults.standard.data(forKey: "actions_\(dateString)"),
           let loadedActions = try? JSONDecoder().decode([SupportingAction].self, from: data) {
            actions = loadedActions.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    // MARK: - Main Goal Operations

    func setMainGoal(_ text: String, for date: Date) {
        let dateString = formatDate(date)
        let goal = MainGoal(
            id: mainGoal?.id ?? UUID().uuidString,
            userId: "",
            date: dateString,
            text: text,
            isComplete: mainGoal?.isComplete ?? false,
            createdAt: mainGoal?.createdAt ?? ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        mainGoal = goal
        saveMainGoal(goal, for: dateString)
    }

    func toggleMainGoalComplete() {
        guard var goal = mainGoal else { return }
        goal.isComplete.toggle()
        goal.updatedAt = ISO8601DateFormatter().string(from: Date())
        mainGoal = goal
        saveMainGoal(goal, for: currentDate)
    }

    func clearMainGoal(for date: Date) {
        let dateString = formatDate(date)
        mainGoal = nil
        UserDefaults.standard.removeObject(forKey: "mainGoal_\(dateString)")
    }

    private func saveMainGoal(_ goal: MainGoal, for dateString: String) {
        if let data = try? JSONEncoder().encode(goal) {
            UserDefaults.standard.set(data, forKey: "mainGoal_\(dateString)")
        }
    }

    // MARK: - Supporting Actions Operations

    func addAction(_ text: String, for date: Date) {
        let dateString = formatDate(date)
        let action = SupportingAction(
            id: UUID().uuidString,
            userId: "",
            date: dateString,
            text: text,
            isComplete: false,
            sortOrder: actions.count,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        actions.append(action)
        saveActions(for: dateString)
    }

    func toggleActionComplete(_ action: SupportingAction) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index].isComplete.toggle()
        actions[index].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveActions(for: currentDate)
    }

    func deleteAction(_ action: SupportingAction) {
        actions.removeAll { $0.id == action.id }
        // Update sort orders
        for i in 0..<actions.count {
            actions[i].sortOrder = i
        }
        saveActions(for: currentDate)
    }

    private func saveActions(for dateString: String) {
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: "actions_\(dateString)")
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
