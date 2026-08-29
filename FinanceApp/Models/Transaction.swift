import Foundation

struct Transaction: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var accountId: UUID
    var categoryId: UUID?
    var type: TransactionType
    var amount: Double
    var description: String
    var note: String?
    var date: String  // "YYYY-MM-DD"
    let createdAt: Date

    enum TransactionType: String, Codable, Sendable {
        case income, expense
    }

    var dateValue: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: date) ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case accountId = "account_id"
        case categoryId = "category_id"
        case type, amount, description, note, date
        case createdAt = "created_at"
    }
}

struct TransactionUpdate: Encodable {
    let categoryId: UUID?
    let type: String
    let amount: Double
    let description: String
    let note: String?
    let date: String

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case type, amount, description, note, date
    }
}

struct TransactionInsert: Encodable {
    let userId: UUID
    let accountId: UUID
    let categoryId: UUID?
    let type: String
    let amount: Double
    let description: String
    let note: String?
    let date: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
        case categoryId = "category_id"
        case type, amount, description, note, date
    }
}
