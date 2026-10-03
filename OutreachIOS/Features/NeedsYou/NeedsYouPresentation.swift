import SwiftUI

/// Needs You in plain words: what kind of reply came in (a pill), why it's
/// waiting on you, and what to do about it - instead of Signal Engine's
/// internal labels ("No safe draft", "Error / blocker").
enum NeedsYouKind: String {
    case outOfOffice = "out_of_office"
    case automated
    case interested
    case question
    case concern
    case notInterested = "not_interested"
    case unsubscribe
    case wrongPerson = "wrong_person"
    case reply

    var label: String {
        switch self {
        case .outOfOffice: return "Out of office"
        case .automated: return "Automated email"
        case .interested: return "Interested"
        case .question: return "Asked a question"
        case .concern: return "Has a concern"
        case .notInterested: return "Not interested"
        case .unsubscribe: return "Asked to stop"
        case .wrongPerson: return "Wrong person"
        case .reply: return "Replied"
        }
    }

    var symbol: String {
        switch self {
        case .outOfOffice: return "airplane"
        case .automated: return "gearshape"
        case .interested: return "hand.thumbsup"
        case .question: return "questionmark.bubble"
        case .concern: return "exclamationmark.bubble"
        case .notInterested: return "hand.thumbsdown"
        case .unsubscribe: return "nosign"
        case .wrongPerson: return "person.fill.questionmark"
        case .reply: return "arrowshape.turn.up.left"
        }
    }

    /// The design's message-type tints: replies green, auto-replies yellow,
    /// bad news pink.
    var tint: Tint {
        switch self {
        case .outOfOffice, .concern: return .yellow
        case .automated: return .neutral
        case .interested, .reply: return .green
        case .question: return .blue
        case .notInterested, .unsubscribe: return .pink
        case .wrongPerson: return .violet
        }
    }

    /// Nothing to answer - the natural next step is Done.
    var needsNoAnswer: Bool { self == .outOfOffice || self == .automated || self == .unsubscribe }
}

/// One pill: what kind of reply, Maya's draft, or a pause.
struct NeedsYouPill: View {
    let label: String
    let symbol: String
    let tint: Tint

    var body: some View {
        TagPill(text: label, tint: tint, symbol: symbol)
    }
}

extension NeedsYouItem {
    var kind: NeedsYouKind {
        NeedsYouKind(rawValue: replyKind ?? "") ?? .reply
    }

    var firstName: String {
        contactName.split(separator: " ").first.map(String.init) ?? contactName
    }

    var initials: String {
        let parts = contactName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// Their message without links, headers or the quoted thread.
    var readableReply: String {
        let clean = (replyClean ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? replyText : clean
    }

    /// The one or two lines the list shows. For an automated email Maya's
    /// summary says more than the email does.
    var listPreview: String {
        if kind == .automated, !replySummary.isEmpty { return replySummary }
        let reply = readableReply
        return reply.isEmpty ? replySummary : reply
    }

    /// Maya stopped on her own (a blocker), not because someone replied.
    var isPaused: Bool { reasonKey == "error_blocker" && kind == .reply }

    /// The pills under the name: the kind of reply, then Maya's draft or a pause.
    var pills: [NeedsYouPill] {
        var pills: [NeedsYouPill] = []
        if isPaused {
            pills.append(NeedsYouPill(label: "Maya paused", symbol: "pause.circle", tint: .yellow))
        } else {
            pills.append(NeedsYouPill(label: kind.label, symbol: kind.symbol, tint: kind.tint))
        }
        if hasMayaDraft {
            pills.append(NeedsYouPill(label: "Reply drafted", symbol: "sparkles", tint: .green))
        }
        return pills
    }

    /// Why this is waiting on you, in a sentence or two, and what to do.
    var why: (title: String, detail: String, suggestion: String) {
        switch kind {
        case .outOfOffice:
            return ("Out-of-office reply", "\(firstName)'s inbox sent an automatic away message, so there's nothing to answer.", "Mark it done to clear it.")
        case .automated:
            return ("Automated email", "This came from a system, not from \(firstName), so there's nothing to answer.", "Mark it done to clear it.")
        case .unsubscribe:
            return ("Asked to stop", "\(firstName) asked not to be emailed again. Maya won't follow up.", "Mark it done once you've seen it.")
        default:
            break
        }
        switch reasonKey {
        case "error_blocker":
            return ("Maya paused this conversation", "Something stopped Maya from following up with \(firstName), so the next step is yours.", "Read the conversation, then reply or mark it done.")
        case "missing_sender":
            return ("No address to send from", "Maya can't reply because this conversation has no sending email set up.", "Connect your inbox, or reply yourself.")
        case "missing_draft_body":
            return ("The draft is empty", "Maya started a reply, but it has no message yet.", "Write the reply yourself.")
        case "approval_required":
            return ("Waiting for your OK", "Maya has a message ready and won't send it without you.", "Review it, then send.")
        case "no_safe_draft":
            return ("\(firstName) replied", "Maya wasn't confident enough to answer this one for you.", "Read what they said and write a reply.")
        default:
            if hasMayaDraft {
                return ("\(firstName) replied", "Maya drafted an answer for you to review.", "Check it, change anything you like, and send.")
            }
            return ("\(firstName) replied", "Replies always come to you before Maya continues.", "Read what they said and reply.")
        }
    }
}

/// A round initials badge in Needs You's pink.
struct NeedsYouAvatar: View {
    let item: NeedsYouItem
    var size: CGFloat = 40

    var body: some View {
        InitialsBadge(name: item.contactName, tint: Area.needsYou.tint, size: size)
    }
}
