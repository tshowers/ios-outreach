import Foundation

/// Pages pushed inside the Outreach dashboard's NavigationStack - no sheets.
enum OutreachRoute: Hashable {
    case inbox
    case message(mailboxId: String, messageId: String)
    case connect(email: String, provider: MailProvider)
    case catalyst
    case catalystCompose(CatalystContact)
    case activity
}
