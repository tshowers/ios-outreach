import Foundation

/// Someone waiting on you - `GET /mobile/outreach/needs-you`
/// (outreach/needsYou.service.js).
struct NeedsYouItem: Decodable, Identifiable, Hashable {
    let contactId: String
    let contactName: String
    let companyName: String
    let email: String
    let phone: String
    let lastSubject: String
    let replyText: String
    let replySummary: String
    let repliedAt: String
    let reasonLabel: String
    let reasonDetail: String
    let nextMove: String
    let mayaDraftSubject: String
    let mayaDraftBody: String
    /// Optional so the app still reads items from a server without them.
    let replyClean: String?
    let replyKind: String?
    let reasonKey: String?

    var id: String { contactId }
    var hasMayaDraft: Bool { !mayaDraftSubject.isEmpty && !mayaDraftBody.isEmpty }

    var repliedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: repliedAt) ?? ISO8601DateFormatter().date(from: repliedAt)
    }

    /// The subject a reply starts with when Maya hasn't drafted one.
    var replySubject: String {
        let subject = lastSubject.trimmingCharacters(in: .whitespaces)
        if subject.isEmpty { return "" }
        return subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }
}

struct NeedsYouListEnvelope: Decodable {
    struct DataBody: Decodable { let items: [NeedsYouItem] }
    let data: DataBody
}

struct NeedsYouDraft: Decodable {
    let subject: String
    let body: String
}

struct NeedsYouDraftEnvelope: Decodable {
    let data: NeedsYouDraft
}

struct NeedsYouSendRequest: Encodable {
    let subject: String
    let body: String
}
