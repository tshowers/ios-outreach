import Foundation

/// The inbox the pre-sign-in wizard asks about: only the email address and
/// its provider - never a password (ONBOARDING-PROFILE-BILLING-PLAYBOOK.md,
/// Outreach). Persisted in UserDefaults so a quit mid-wizard resumes; after
/// sign-in ConnectInboxView hands it to outreach.taliferro.tech's Inbox
/// Access page, already signed in, where Gmail connects with Google and
/// other providers take an app password on that signed-in page.
struct InboxDraft: Codable, Equatable {
    var emailAddress = ""
    var provider: MailProvider = .gmail
    /// Set when the user picked a provider themselves, so typing the address
    /// again doesn't overwrite their choice.
    var providerChosenByUser = false
    var isReadyToSubmit = false

    private static let storageKey = "outreach.inboxDraft"

    static func load() -> InboxDraft {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let draft = try? JSONDecoder().decode(InboxDraft.self, from: data) else {
            return InboxDraft()
        }
        return draft
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    var trimmedEmail: String { emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var isValidEmail: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }

    /// Picked in the wizard and waiting to be connected after sign-in.
    var isPendingConnect: Bool { isReadyToSubmit && isValidEmail }

    /// Follows the address as it's typed until the user picks one.
    mutating func detectProvider() {
        guard !providerChosenByUser else { return }
        provider = MailProvider.detect(from: trimmedEmail)
    }

    /// outreach.taliferro.tech/inbox-access, pre-filled with this address.
    var inboxAccessPath: String {
        var components = URLComponents()
        components.path = "/inbox-access"
        components.queryItems = [
            URLQueryItem(name: "email", value: trimmedEmail),
            URLQueryItem(name: "provider", value: provider.rawValue),
        ]
        return components.string ?? "/inbox-access"
    }
}

/// Mirrors the backend's MAILBOX_PROVIDER_PRESETS (mail-provider-config.js).
enum MailProvider: String, Codable, CaseIterable, Identifiable {
    case gmail
    case outlook
    case icloud
    case yahoo
    case otherImap = "other_imap"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gmail: return "Gmail / Google Workspace"
        case .outlook: return "Outlook / Microsoft 365"
        case .icloud: return "iCloud"
        case .yahoo: return "Yahoo"
        case .otherImap: return "Other"
        }
    }

    /// What connecting will ask for - shown before sign-in so nothing is a
    /// surprise.
    var howItConnects: String {
        switch self {
        case .gmail:
            return "Google will ask you once to let Outreach read replies and send from this inbox - that's separate from signing in. TODD never sees your password."
        case .outlook, .icloud, .yahoo:
            return "You'll create an app password with \(label) and paste it in once. It's not your regular password, and you can revoke it any time."
        case .otherImap:
            return "You'll enter your mail server settings and an app password once, on a secure signed-in page."
        }
    }

    static func detect(from email: String) -> MailProvider {
        let domain = email.split(separator: "@").last.map(String.init) ?? ""
        switch domain {
        case "gmail.com", "googlemail.com": return .gmail
        case "outlook.com", "hotmail.com", "live.com", "office365.com", "msn.com": return .outlook
        case "icloud.com", "me.com", "mac.com": return .icloud
        case "yahoo.com", "ymail.com", "rocketmail.com": return .yahoo
        // A work domain is most often Google Workspace; the chips let them change it.
        default: return .gmail
        }
    }
}
