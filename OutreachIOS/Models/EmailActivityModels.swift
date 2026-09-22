import Foundation

/// Mirrors (a subset of) the record shape
/// `outreach/email/email.service.js`'s `listEmails` returns. Decoded
/// defensively (everything but `id` is optional) since this mobile client
/// only needs a read-only activity glance, not the full Outbox cockpit
/// model - per docs/app-store-exclusive-billing-plan.md, Outreach's native
/// app scope is "/app only".
struct EmailActivityRecord: Codable, Identifiable {
    let id: String
    var subject: String?
    var to: String?
    var from: String?
    var opened: Bool?
    var date: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        opened = try container.decodeIfPresent(Bool.self, forKey: .opened)
        date = try container.decodeIfPresent(String.self, forKey: .date)
    }
}

struct EmailActivityData: Codable {
    let records: [EmailActivityRecord]
    let count: Int?
    let hasMore: Bool?
}

struct EmailActivityEnvelope: Codable {
    let success: Bool
    let data: EmailActivityData
}
