import Foundation

struct Category: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID?
    var name: String
    var type: CategoryType
    var icon: String
    var color: String

    enum CategoryType: String, Codable, Sendable {
        case income, expense
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, type, icon, color
    }
}
