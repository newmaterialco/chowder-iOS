import Foundation

struct SavedSession: Identifiable, Codable, Equatable {
    let id: UUID
    var key: String          // e.g. "agent:main:main"
    var label: String        // user-friendly label e.g. "Main", "Research"
    var lastUsed: Date
    var messageCount: Int

    init(id: UUID = UUID(), key: String, label: String, lastUsed: Date = Date(), messageCount: Int = 0) {
        self.id = id
        self.key = key
        self.label = label
        self.lastUsed = lastUsed
        self.messageCount = messageCount
    }

    /// Default session matching the app's initial config.
    static var defaultSession: SavedSession {
        SavedSession(key: "agent:main:main", label: "Main")
    }
}
