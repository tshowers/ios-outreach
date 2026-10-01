import Foundation

/// One of Maya's drafts waiting for a decision - `GET /mobile/outreach/drafts`
/// (outreach/draftsMobile.service.js).
struct DraftItem: Decodable, Identifiable, Hashable {
    let contactId: String
    let contactName: String
    let companyName: String
    let email: String
    /// "outbound" (first touch / follow-up) or "reply".
    let kind: String
    let subject: String
    let body: String
    let rationale: String
    let stage: String
    let updatedAt: String

    var id: String { contactId }
    var isReply: Bool { kind == "reply" }
}

struct DraftsEnvelope: Decodable {
    struct DataBody: Decodable {
        let items: [DraftItem]
        let rewritingCount: Int
    }
    let data: DataBody
}

struct DraftApproveRequest: Encodable {
    let subject: String
    let body: String
}

struct DraftRejectRequest: Encodable {
    let reason: String
}

struct DraftBatchRequest: Encodable {
    let contactIds: [String]
}

struct DraftBatchEnvelope: Decodable {
    struct DataBody: Decodable {
        let approvedCount: Int?
        let queuedCount: Int?
        let failedCount: Int?
    }
    let data: DataBody?
}
