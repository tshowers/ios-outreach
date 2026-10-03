import Foundation

struct PushDeviceRequest: Encodable {
    let token: String
    let app: String
    let environment: String
    let appVersion: String
}

/// One switch per kind of notification (push.service.js APPS.outreach).
struct PushPreferences: Codable, Equatable {
    var replies: Bool = true
    var mailbox: Bool = true
    var catalyst: Bool = true
    var sendingApproved: Bool = true
    var maya: Bool = true

    enum CodingKeys: String, CodingKey {
        case replies, mailbox, catalyst, maya
        case sendingApproved = "sending_approved"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replies = try container.decodeIfPresent(Bool.self, forKey: .replies) ?? true
        mailbox = try container.decodeIfPresent(Bool.self, forKey: .mailbox) ?? true
        catalyst = try container.decodeIfPresent(Bool.self, forKey: .catalyst) ?? true
        sendingApproved = try container.decodeIfPresent(Bool.self, forKey: .sendingApproved) ?? true
        maya = try container.decodeIfPresent(Bool.self, forKey: .maya) ?? true
    }
}

struct PushPreferencesRequest: Encodable {
    let app: String
    let preferences: PushPreferences
}

struct PushPreferencesEnvelope: Decodable {
    let preferences: PushPreferences
}

/// One entry in the Activity history - everything Outreach and Maya
/// notified about, including what quiet hours or a switched-off category
/// kept off the lock screen.
struct ActivityItem: Decodable, Identifiable, Hashable {
    let id: String
    let category: String
    let title: String
    let body: String?
    let route: String?
    let createdAt: String

    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }

    var systemImage: String {
        switch category {
        case "replies": return "arrowshape.turn.up.left"
        case "mailbox": return "exclamationmark.triangle"
        case "catalyst": return "bolt"
        case "sending_approved": return "checkmark.seal"
        case "maya": return "sparkle"
        default: return "bell"
        }
    }
}

struct ActivityEnvelope: Decodable {
    let items: [ActivityItem]
}
