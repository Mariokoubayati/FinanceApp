import Foundation

struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var fullName: String?
    var currency: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case currency
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
