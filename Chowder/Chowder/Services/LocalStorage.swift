import UIKit

/// Lightweight file-based persistence for user data.
/// All files live in the app's Documents directory.
/// When migrating to a backend, replace the implementations here.
enum LocalStorage {

    // MARK: - Directories

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Per-session directory for message storage.
    private static func sessionDirectory(for sessionKey: String) -> URL {
        let sanitized = sessionKey
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let dir = documentsURL.appendingPathComponent("sessions/\(sanitized)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Chat History (per-session)

    static func saveMessages(_ messages: [Message], forSession sessionKey: String) {
        let url = sessionDirectory(for: sessionKey).appendingPathComponent("chat_history.json")
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save messages: \(error)")
        }
    }

    static func loadMessages(forSession sessionKey: String) -> [Message] {
        let url = sessionDirectory(for: sessionKey).appendingPathComponent("chat_history.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let messages = try JSONDecoder().decode([Message].self, from: data)
                if !messages.isEmpty {
                    return messages
                }
                // File exists but is empty — fall through to legacy
            } catch {
                print("[LocalStorage] Failed to load per-session messages: \(error)")
                // Fall through to legacy on decode error (e.g. schema change)
            }
        }

        // Migration: try loading from legacy location
        let legacy = loadLegacyMessages()
        if !legacy.isEmpty {
            print("[LocalStorage] Migrated \(legacy.count) messages from legacy to session \(sessionKey)")
            // Save to per-session location so we don't migrate again
            saveMessages(legacy, forSession: sessionKey)
        }
        return legacy
    }

    static func deleteMessages(forSession sessionKey: String) {
        let url = sessionDirectory(for: sessionKey).appendingPathComponent("chat_history.json")
        try? FileManager.default.removeItem(at: url)
    }

    // Legacy support (single-session)
    private static var chatHistoryURL: URL {
        documentsURL.appendingPathComponent("chat_history.json")
    }

    private static func loadLegacyMessages() -> [Message] {
        guard FileManager.default.fileExists(atPath: chatHistoryURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: chatHistoryURL)
            return try JSONDecoder().decode([Message].self, from: data)
        } catch {
            print("[LocalStorage] Failed to load legacy messages: \(error)")
            return []
        }
    }

    // MARK: - Saved Sessions

    private static var sessionsURL: URL {
        documentsURL.appendingPathComponent("saved_sessions.json")
    }

    static func saveSessions(_ sessions: [SavedSession]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: sessionsURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save sessions: \(error)")
        }
    }

    static func loadSessions() -> [SavedSession] {
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: sessionsURL)
            return try JSONDecoder().decode([SavedSession].self, from: data)
        } catch {
            print("[LocalStorage] Failed to load sessions: \(error)")
            return []
        }
    }

    // MARK: - Agent Avatar

    private static var avatarURL: URL {
        documentsURL.appendingPathComponent("agent_avatar.jpg")
    }

    static func saveAvatar(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: avatarURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save avatar: \(error)")
        }
        SharedStorage.saveAvatar(image)
    }

    static func loadAvatar() -> UIImage? {
        guard FileManager.default.fileExists(atPath: avatarURL.path) else { return nil }
        return UIImage(contentsOfFile: avatarURL.path)
    }

    static func deleteAvatar() {
        try? FileManager.default.removeItem(at: avatarURL)
        SharedStorage.deleteAvatar()
    }

    // MARK: - User Context (legacy local-only)

    private static var userContextURL: URL {
        documentsURL.appendingPathComponent("user_context.json")
    }

    static func saveUserContext(_ context: UserContext) {
        do {
            let data = try JSONEncoder().encode(context)
            try data.write(to: userContextURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save user context: \(error)")
        }
    }

    static func loadUserContext() -> UserContext {
        guard FileManager.default.fileExists(atPath: userContextURL.path) else { return UserContext() }
        do {
            let data = try Data(contentsOf: userContextURL)
            return try JSONDecoder().decode(UserContext.self, from: data)
        } catch {
            print("[LocalStorage] Failed to load user context: \(error)")
            return UserContext()
        }
    }

    static func deleteUserContext() {
        try? FileManager.default.removeItem(at: userContextURL)
    }

    // MARK: - Bot Identity (cache of IDENTITY.md)

    private static var botIdentityURL: URL {
        documentsURL.appendingPathComponent("bot_identity.json")
    }

    static func saveBotIdentity(_ identity: BotIdentity) {
        do {
            let data = try JSONEncoder().encode(identity)
            try data.write(to: botIdentityURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save bot identity: \(error)")
        }
    }

    static func loadBotIdentity() -> BotIdentity {
        guard FileManager.default.fileExists(atPath: botIdentityURL.path) else { return BotIdentity() }
        do {
            let data = try Data(contentsOf: botIdentityURL)
            return try JSONDecoder().decode(BotIdentity.self, from: data)
        } catch {
            print("[LocalStorage] Failed to load bot identity: \(error)")
            return BotIdentity()
        }
    }

    // MARK: - User Profile (cache of USER.md)

    private static var userProfileURL: URL {
        documentsURL.appendingPathComponent("user_profile.json")
    }

    static func saveUserProfile(_ profile: UserProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: userProfileURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save user profile: \(error)")
        }
    }

    static func loadUserProfile() -> UserProfile {
        guard FileManager.default.fileExists(atPath: userProfileURL.path) else { return UserProfile() }
        do {
            let data = try Data(contentsOf: userProfileURL)
            return try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            print("[LocalStorage] Failed to load user profile: \(error)")
            return UserProfile()
        }
    }
}
