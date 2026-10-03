import Foundation

/// What kind of email this is, for the Inbox tag and filters (design 4e).
/// The server's `classification` only covers replies from contacts, so the
/// type comes from the sender, subject and text - the same rules the server
/// uses for Needs You (outreach/replyText.js).
enum MessageKind: Hashable {
    case reply, outOfOffice, bounce, forward, newsletter

    var label: String {
        switch self {
        case .reply: return "Reply"
        case .outOfOffice: return "Out of office"
        case .bounce: return "Bounce"
        case .forward: return "Forward"
        case .newsletter: return "Newsletter"
        }
    }

    var tint: Tint {
        switch self {
        case .reply: return .green
        case .outOfOffice: return .yellow
        case .bounce: return .pink
        case .forward: return .blue
        case .newsletter: return .neutral
        }
    }
}

extension MailboxMessage {
    var kind: MessageKind {
        let subject = (self.subject ?? "").lowercased()
        let from = (fromEmail ?? "").lowercased()
        let text = "\(subject)\n\(preview ?? "")\n\(self.text ?? "")".lowercased()

        if from.contains("mailer-daemon") || from.contains("postmaster") ||
            ["delivery status notification", "undeliverable", "mail delivery failed", "returned mail", "delivery has failed"].contains(where: subject.contains) ||
            text.range(of: #"(address|account|email) (is )?no longer (active|in use|valid|monitored)|no longer with (the company|us)"#, options: .regularExpression) != nil {
            return .bounce
        }
        if ["automatic reply", "auto:", "autoreply", "auto-reply", "out of office", "out of the office"].contains(where: subject.hasPrefix) ||
            text.range(of: #"out of (the )?office|\booo\b|on (annual |parental |maternity |paternity )?leave|limited (access to )?e-?mail|will (be )?(return|back) (on|by|after)"#, options: .regularExpression) != nil {
            return .outOfOffice
        }
        if subject.hasPrefix("fw:") || subject.hasPrefix("fwd:") {
            return .forward
        }
        // Senders only: replies to Outreach quote its unsubscribe footer, and
        // small businesses answer from info@ or hello@.
        if from.range(of: #"(no-?reply|do-?not-?reply|newsletter|news|marketing|notifications?|updates)@"#, options: .regularExpression) != nil {
            return .newsletter
        }
        return .reply
    }

    /// One line for the list: TODD's read when there is one, otherwise the
    /// start of the message without links, headers or quoted text.
    var summaryLine: String {
        if let summary = signalSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        return MessageText.clean(preview ?? text ?? "").replacingOccurrences(of: "\n", with: " ")
    }
}

/// Readable email text: no tracking links, link-defense wrappers, header
/// blocks or the quoted thread (a Swift port of the server's cleanReplyText).
enum MessageText {
    static func clean(_ raw: String) -> String {
        let withoutLinks = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            // A separator run inside a flattened one-line preview still
            // starts the quoted part.
            .replacingOccurrences(of: #"[_=]{5,}"#, with: "\n-----\n", options: .regularExpression)
            .replacingOccurrences(of: #"\[(?:cid:|https?://)[^\]]*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<(?:mailto:|https?://)[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)

        var own: [String] = []
        var quoted: [String]?
        for rawLine in withoutLinks.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let isMarker = line.range(of: #"^on .{3,200}wrote:?$|^-{2,}\s*(original|forwarded) message\s*-{2,}$|^begin forwarded message:?$|^[\s_\-=*]{5,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
            if isMarker || line.hasPrefix(">") {
                quoted = []
                continue
            }
            if quoted != nil { quoted?.append(line) } else { own.append(line) }
        }
        let isHeader: (String) -> Bool = { $0.range(of: #"^(from|sent|to|cc|bcc|date|subject|reply-to):\s"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let hasOwnText = own.contains { !$0.isEmpty && !isHeader($0) }
        let kept = hasOwnText ? own : (quoted ?? own).filter { !isHeader($0) }
        return kept
            .filter { $0.range(of: #"^[\w ]{1,30}:$"#, options: .regularExpression) == nil }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
