import SwiftUI

@Observable
@MainActor
final class SavingsViewModel {
    var goals: [SavingsGoal] = []
    var isLoading = false
    var errorMessage: String?

    func load(userId: UUID) async {
        isLoading = true
        do {
            goals = try await SavingsService.shared.fetchAll(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func create(userId: UUID, name: String, targetAmount: Double, targetDate: Date?, icon: String, color: String) async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"

        let insert = SavingsGoalInsert(
            userId: userId,
            name: name,
            targetAmount: targetAmount,
            targetDate: targetDate.map { f.string(from: $0) },
            icon: icon,
            color: color
        )

        do {
            let goal = try await SavingsService.shared.create(insert)
            goals.insert(goal, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addContribution(to goal: SavingsGoal, amount: Double) async {
        let newAmount    = goal.currentAmount + amount
        let isCompleted  = newAmount >= goal.targetAmount

        do {
            try await SavingsService.shared.updateProgress(goalId: goal.id, newAmount: newAmount, isCompleted: isCompleted)
            if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[idx].currentAmount = newAmount
                goals[idx].isCompleted   = isCompleted
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ goal: SavingsGoal) async {
        do {
            try await SavingsService.shared.delete(id: goal.id)
            goals.removeAll { $0.id == goal.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
