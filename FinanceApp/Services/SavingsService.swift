import Foundation

final class SavingsService: Sendable {
    static let shared = SavingsService()
    private init() {}

    func fetchAll(userId: UUID) async throws -> [SavingsGoal] {
        try await supabase
            .from("savings_goals")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func create(_ insert: SavingsGoalInsert) async throws -> SavingsGoal {
        try await supabase
            .from("savings_goals")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
    }

    func updateProgress(goalId: UUID, newAmount: Double, isCompleted: Bool) async throws {
        try await supabase
            .from("savings_goals")
            .update(SavingsGoalProgressUpdate(currentAmount: newAmount, isCompleted: isCompleted))
            .eq("id", value: goalId)
            .execute()
    }

    func delete(id: UUID) async throws {
        try await supabase
            .from("savings_goals")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
