import Foundation

final class TransactionService: Sendable {
    static let shared = TransactionService()
    private init() {}

    func fetchRecent(userId: UUID, limit: Int = 5) async throws -> [Transaction] {
        try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func fetchAll(userId: UUID, limit: Int = 200) async throws -> [Transaction] {
        try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func fetchForMonth(userId: UUID, year: Int, month: Int) async throws -> [Transaction] {
        let nextMonth = month == 12 ? 1 : month + 1
        let nextYear  = month == 12 ? year + 1 : year
        let start = String(format: "%04d-%02d-01", year, month)
        let end   = String(format: "%04d-%02d-01", nextYear, nextMonth)

        return try await supabase
            .from("transactions")
            .select()
            .eq("user_id", value: userId)
            .gte("date", value: start)
            .lt("date", value: end)
            .order("date", ascending: false)
            .execute()
            .value
    }

    func insert(_ transaction: TransactionInsert) async throws -> Transaction {
        try await supabase
            .from("transactions")
            .insert(transaction)
            .select()
            .single()
            .execute()
            .value
    }

    func update(id: UUID, _ payload: TransactionUpdate) async throws -> Transaction {
        try await supabase
            .from("transactions")
            .update(payload)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func delete(id: UUID) async throws {
        try await supabase
            .from("transactions")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func fetchCategories() async throws -> [Category] {
        try await supabase
            .from("categories")
            .select()
            .order("name")
            .execute()
            .value
    }
}
