import Foundation

/// Mirrors the web app's MailboxConfigSummary / MailboxMessageListItem /
/// MailboxMessageDetail (outreach-api.service.ts) - what
/// outreach/mailboxes/mailbox.service.js returns. Almost everything is
/// optional so an older or partial record never fails to decode.
struct MailboxSummary: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String?
    let emailAddress: String
    let provider: String?
    let providerLabel: String?
    let isPrimary: Bool?
    let lastSyncAt: String?
    let lastSyncStatus: String?
    let lastConnectionStatus: String?

    var title: String { emailAddress }
    var subtitle: String {
        [providerLabel ?? provider, isPrimary == true ? "Primary" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

struct MailboxAddress: Decodable, Hashable {
    let name: String?
    let email: String
}

struct MailboxMessage: Decodable, Identifiable, Hashable {
    let id: String
    let mailboxId: String?
    let subject: String?
    let fromName: String?
    let fromEmail: String?
    let receivedAt: String?
    let unread: Bool?
    let replied: Bool?
    let hasAttachments: Bool?
    let preview: String?
    let classification: String?
    let signalSummary: String?
    let recommendedAction: String?
    let replyDraftSubject: String?
    let replyDraftBody: String?
    // Detail only
    let to: [MailboxAddress]?
    let text: String?
    let html: String?

    var sender: String { (fromName?.isEmpty == false ? fromName : fromEmail) ?? "Unknown sender" }
    var displaySubject: String { subject?.isEmpty == false ? subject! : "(No subject)" }

    var receivedDate: Date? {
        guard let receivedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: receivedAt) ?? ISO8601DateFormatter().date(from: receivedAt)
    }

    /// The message body as plain text - the text part, or the HTML part with
    /// tags stripped.
    var bodyText: String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        guard let html else { return preview ?? "" }
        let withBreaks = html.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>", with: "\n", options: .regularExpression)
        let stripped = withBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MailboxServerSettings: Encodable {
    var host: String
    var port: Int
    var secure: Bool
}

/// `POST /mailboxes` and `/mailboxes/test` - app-password connections.
/// Known providers only need the address and app password; the backend
/// fills in their server settings (mail-provider-config.js).
struct MailboxConnectRequest: Encodable {
    var emailAddress: String
    var provider: String
    var secret: String
    var displayName: String?
    var imap: MailboxServerSettings?
    var smtp: MailboxServerSettings?
}

struct MailboxReplyRequest: Encodable {
    let subject: String
    let body: String
    let text: String
}

struct GoogleMailboxStart: Decodable {
    let url: String
}

struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

struct ServerMessage: Decodable {
    let message: String?
}
