import Foundation

struct SavingsGoal: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    var name: String
    var targetAmount: Double
    var currentAmount: Double
    var targetDate: String?
    var icon: String
    var color: String
    var isCompleted: Bool
    let createdAt: Date
    var updatedAt: Date

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }

    var remaining: Double {
        max(targetAmount - currentAmount, 0)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case targetAmount = "target_amount"
        case currentAmount = "current_amount"
        case targetDate = "target_date"
        case icon, color
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SavingsGoalInsert: Encodable {
    let userId: UUID
    let name: String
    let targetAmount: Double
    let targetDate: String?
    let icon: String
    let color: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case icon, color
    }
}

struct SavingsGoalProgressUpdate: Encodable {
    let currentAmount: Double
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case currentAmount = "current_amount"
        case isCompleted = "is_completed"
    }
}
