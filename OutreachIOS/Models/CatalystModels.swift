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
    /// The History run this send counts toward (nil for a test send).
    let catalystRunId: String?
}

/// The "Ready to Send" card - `GET /mobile/outreach/catalyst/sending-status`
/// (the web's email-sending-status, worked out on the server).
struct CatalystSendingStatus: Decodable {
    let level: String
    let label: String
    let detail: String
    let campaignHint: String
    let capForToday: Int
    let usedToday: Int
    let remainingToday: Int

    var isReady: Bool { level == "ready" }
}

/// One batch in Catalyst History - `GET /mobile/outreach/catalyst/runs`.
struct CatalystRun: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String
    let queuedCount: Int
    let skippedCount: Int
    let sentCount: Int
    let uniqueOpenedCount: Int
    let uniqueClickedCount: Int
    let openRate: Double
    let clickRate: Double
    let startedAt: String
    let completedAt: String

    var startedDate: Date? { CatalystRun.parse(startedAt) }
    var completedDate: Date? { CatalystRun.parse(completedAt) }

    private static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct CatalystRunCreateRequest: Encodable {
    let contactIds: [String]
    let plannedCount: Int
}

struct CatalystRunFinalizeRequest: Encodable {
    let status: String
    let queuedCount: Int
    let skippedCount: Int
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

/// The draft arrives as HTML (with the signature); it's edited here as
/// plain text and sent back as simple HTML paragraphs.
enum CatalystText {
    static func plainText(fromHTML html: String) -> String {
        let withBreaks = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</(p|div|li|h[1-6])>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        let stripped = withBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return decoded
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func html(fromPlainText text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return escaped
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined()
    }
}
