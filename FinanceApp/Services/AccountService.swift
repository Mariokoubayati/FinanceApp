import Foundation

final class AccountService: Sendable {
    static let shared = AccountService()
    private init() {}

    func fetchAll(userId: UUID) async throws -> [Account] {
        try await supabase
            .from("accounts")
            .select()
            .eq("user_id", value: userId)
            .eq("is_active", value: true)
            .order("created_at")
            .execute()
            .value
    }

    func create(_ insert: AccountInsert) async throws -> Account {
        try await supabase
            .from("accounts")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
    }

    func updateBalance(accountId: UUID, newBalance: Double) async throws {
        try await supabase
            .from("accounts")
            .update(AccountBalanceUpdate(balance: newBalance))
            .eq("id", value: accountId)
            .execute()
    }

    func softDelete(id: UUID) async throws {
        try await supabase
            .from("accounts")
            .update(["is_active": false])
            .eq("id", value: id)
            .execute()
    }
}
