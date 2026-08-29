import Foundation

final class BudgetService: Sendable {
    static let shared = BudgetService()
    private init() {}

    func fetchAll(userId: UUID) async throws -> [Budget] {
        try await supabase
            .from("budgets")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    func upsert(_ budget: BudgetUpsert) async throws -> Budget {
        try await supabase
            .from("budgets")
            .upsert(budget, onConflict: "user_id,category_id")
            .select()
            .single()
            .execute()
            .value
    }

    func delete(id: UUID) async throws {
        try await supabase
            .from("budgets")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
