import Foundation

/// One person in the Catalyst queue - `GET /mobile/outreach/catalyst/queue`
/// (catalystMobile.service.js buildStaleQueue): eligible contacts, stalest
/// first, same rules as web Catalyst.
struct CatalystContact: Decodable, Identifiable, Hashable {
    let id: String
    let firstName: String
    let lastName: String?
    let companyName: String?
    let email: String?
    let profession: String?
    let daysSinceLastContact: Int

    var fullName: String {
        [firstName, lastName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var staleLabel: String {
        switch daysSinceLastContact {
        case 0: return "Contacted today"
        case 1: return "1 day since last contact"
        default: return "\(daysSinceLastContact) days since last contact"
        }
    }
}

/// TODD's draft for one contact - `POST /mobile/outreach/catalyst/draft`.
struct CatalystDraft: Decodable {
    let subject: String
    let bodyHtml: String
}

struct CatalystDraftRequest: Encodable {
    let contactId: String
    let tone: String
}

struct CatalystSendRequest: Encodable {
    let contactId: String
    let subject: String
    let html: String
}

/// Whatever /send-email answered - Catalyst sends are usually queued for
/// business hours rather than sent that second.
struct CatalystSendResult: Decodable {
    let scheduled: Bool?
    let queued: Bool?
    let message: String?

    var wasQueued: Bool { scheduled == true || queued == true }
}

/// The drafting service's tones (emailDrafting.service.js DRAFTING_METADATA).
enum CatalystTone: String, CaseIterable, Identifiable {
    case direct, warm, concise, consultative

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var hint: String {
        switch self {
        case .direct: return "Short, clear, and practical."
        case .warm: return "Friendly and natural without overselling."
        case .concise: return "Minimal words, easy to scan."
        case .consultative: return "Guiding, thoughtful, and problem-aware."
        }
    }
}
