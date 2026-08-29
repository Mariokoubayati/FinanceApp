import Foundation

struct Account: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var name: String
    var type: AccountType
    var balance: Double
    var currency: String
    var color: String
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date

    enum AccountType: String, Codable, CaseIterable, Sendable {
        case bank, cash, credit, savings

        var displayName: String {
            switch self {
            case .bank:    return "Bank Account"
            case .cash:    return "Cash"
            case .credit:  return "Credit Card"
            case .savings: return "Savings Account"
            }
        }

        var icon: String {
            switch self {
            case .bank:    return "building.columns.fill"
            case .cash:    return "banknote.fill"
            case .credit:  return "creditcard.fill"
            case .savings: return "piggybank.fill"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, type, balance, currency, color
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct AccountInsert: Encodable {
    let userId: UUID
    let name: String
    let type: String
    let balance: Double
    let currency: String
    let color: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, type, balance, currency, color
    }
}

struct AccountBalanceUpdate: Encodable {
    let balance: Double
}
