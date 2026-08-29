import Foundation

struct Budget: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let categoryId: UUID
    var monthlyLimit: Double
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case categoryId  = "category_id"
        case monthlyLimit = "monthly_limit"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}

struct BudgetUpsert: Encodable {
    let userId: UUID
    let categoryId: UUID
    let monthlyLimit: Double

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case categoryId  = "category_id"
        case monthlyLimit = "monthly_limit"
    }
}
