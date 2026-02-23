import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct Message: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var imageData: Data?

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), imageData: Data? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.imageData = imageData
    }
}
