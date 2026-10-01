import Foundation

enum OutreachAPIError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case httpError(Int)
    /// The backend's own explanation (its JSON `message`), e.g. "Mailbox
    /// app password required" - clearer than a status code.
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to load your email activity."
        case .invalidResponse:
            return "The server response could not be understood."
        case .httpError(let code):
            return "The server returned HTTP \(code)."
        case .server(_, let message):
            return message
        }
    }
}

/// Talks to `todd-backend`'s /api/mobile/outreach/* endpoints
/// (outreachMobileRoutes.js) - a verified-token surface reusing
/// email.controller.js's existing listEmails logic, same pattern as
/// network-ios's NetworkAPIClient.
final class OutreachAPIClient {
    private let config: AppConfig
    private let authService: AuthService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: AppConfig, authService: AuthService) {
        self.config = config
        self.authService = authService
    }

    func fetchEmailActivity() async throws -> [EmailActivityRecord] {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/emails")
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(EmailActivityEnvelope.self, from: data).data.records
    }

    func fetchSignalEngineStatus() async throws -> SignalEngineSummary {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/status")
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(SignalEngineBootstrapEnvelope.self, from: data).data.summary
    }

    func fetchProgress() async throws -> OutreachProgress {
        let url = config.apiBaseURL.appending(path: "getting-started/outreach")
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(OutreachProgressEnvelope.self, from: data).data
    }

    func linkAppStorePurchase(appAccountToken: String) async throws {
        let payload = AppStoreLinkRequest(appAccountToken: appAccountToken, productKey: "outreach")
        let url = config.apiBaseURL.appending(path: "app-store/link")
        _ = try await authorizedRequest(method: "POST", url: url, body: try encoder.encode(payload))
    }

    /// Sends a StoreKit transaction's signed JWS right after a purchase or
    /// restore; the backend verifies Apple's signature and returns the fresh
    /// entitlement - an immediate unlock that doesn't depend on Apple's
    /// server notification.
    func submitAppStoreTransaction(signedTransaction: String) async throws -> AppStoreEntitlement {
        let url = config.apiBaseURL.appending(path: "app-store/transactions/outreach")
        let body = try encoder.encode(AppStoreTransactionRequest(signedTransaction: signedTransaction))
        let data = try await authorizedRequest(method: "POST", url: url, body: body)
        return try decoder.decode(AppStoreEntitlementEnvelope.self, from: data).entitlement
    }

    func fetchAppStoreEntitlement() async throws -> AppStoreEntitlement {
        let url = config.apiBaseURL.appending(path: "app-store/entitlement/outreach")
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(AppStoreEntitlementEnvelope.self, from: data).entitlement
    }

    // MARK: - Inbox (outreachMobileRoutes.js /mobile/outreach/mailboxes)

    func fetchMailboxes() async throws -> [MailboxSummary] {
        let data = try await authorizedRequest(method: "GET", url: mailboxURL())
        return try decoder.decode(DataEnvelope<[MailboxSummary]>.self, from: data).data
    }

    func fetchMessages(mailboxId: String, limit: Int = 50) async throws -> [MailboxMessage] {
        var url = mailboxURL(mailboxId, "messages")
        url.append(queryItems: [URLQueryItem(name: "limit", value: String(limit))])
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(DataEnvelope<[MailboxMessage]>.self, from: data).data
    }

    func fetchMessage(mailboxId: String, messageId: String) async throws -> MailboxMessage {
        let data = try await authorizedRequest(method: "GET", url: mailboxURL(mailboxId, "messages", messageId))
        return try decoder.decode(DataEnvelope<MailboxMessage>.self, from: data).data
    }

    func syncMailbox(mailboxId: String) async throws {
        _ = try await authorizedRequest(method: "POST", url: mailboxURL(mailboxId, "sync"), body: Data("{}".utf8))
    }

    func setPrimaryMailbox(mailboxId: String) async throws {
        _ = try await authorizedRequest(method: "POST", url: mailboxURL(mailboxId, "set-primary"), body: Data("{}".utf8))
    }

    func reply(mailboxId: String, messageId: String, subject: String, body: String) async throws {
        let payload = try encoder.encode(MailboxReplyRequest(subject: subject, body: body, text: body))
        _ = try await authorizedRequest(method: "POST", url: mailboxURL(mailboxId, "messages", messageId, "reply"), body: payload)
    }

    func deleteMessage(mailboxId: String, messageId: String) async throws {
        _ = try await authorizedRequest(method: "DELETE", url: mailboxURL(mailboxId, "messages", messageId))
    }

    func disconnectMailbox(mailboxId: String) async throws {
        _ = try await authorizedRequest(method: "DELETE", url: mailboxURL(mailboxId))
    }

    /// Checks the address and app password work (IMAP and SMTP) without saving.
    func testMailbox(_ request: MailboxConnectRequest) async throws {
        _ = try await authorizedRequest(method: "POST", url: mailboxURL("test"), body: try encoder.encode(request))
    }

    @discardableResult
    func saveMailbox(_ request: MailboxConnectRequest) async throws -> MailboxSummary {
        let data = try await authorizedRequest(method: "POST", url: mailboxURL(), body: try encoder.encode(request))
        return try decoder.decode(DataEnvelope<MailboxSummary>.self, from: data).data
    }

    /// Google's approval page; it returns to the app
    /// (`tech.taliferro.outreachios://mailbox-connected?status=...`).
    func startGoogleMailboxConnection() async throws -> URL {
        let body = try encoder.encode(["client": "ios"])
        let data = try await authorizedRequest(method: "POST", url: mailboxURL("oauth", "google", "start"), body: body)
        let start = try decoder.decode(DataEnvelope<GoogleMailboxStart>.self, from: data).data
        guard let url = URL(string: start.url) else { throw OutreachAPIError.invalidResponse }
        return url
    }

    // MARK: - Catalyst (/mobile/outreach/catalyst/*)

    func fetchCatalystQueue() async throws -> [CatalystContact] {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/catalyst/queue")
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(DataEnvelope<[CatalystContact]>.self, from: data).data
    }

    func draftCatalystEmail(contactId: String, tone: CatalystTone) async throws -> CatalystDraft {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/catalyst/draft")
        let body = try encoder.encode(CatalystDraftRequest(contactId: contactId, tone: tone.rawValue))
        let data = try await authorizedRequest(method: "POST", url: url, body: body)
        return try decoder.decode(DataEnvelope<CatalystDraft>.self, from: data).data
    }

    /// The server builds the email from its own records (recipient from the
    /// contact, sender from your account) - only the subject and body come
    /// from here.
    func sendCatalystEmail(contactId: String, subject: String, html: String) async throws -> CatalystSendResult {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/catalyst/send")
        let body = try encoder.encode(CatalystSendRequest(contactId: contactId, subject: subject, html: html))
        let data = try await authorizedRequest(method: "POST", url: url, body: body)
        return (try? decoder.decode(CatalystSendResult.self, from: data)) ?? CatalystSendResult(scheduled: nil, queued: nil, message: nil)
    }

    private func mailboxURL(_ components: String...) -> URL {
        components.reduce(config.apiBaseURL.appending(path: "mobile/outreach/mailboxes")) { url, component in
            url.appending(path: component)
        }
    }

    // MARK: - Needs You (/mobile/outreach/needs-you)

    func fetchNeedsYou() async throws -> [NeedsYouItem] {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/needs-you")
        let data = try await authorizedRequest(method: "GET", url: url)
        return try decoder.decode(NeedsYouListEnvelope.self, from: data).data.items
    }

    func draftNeedsYouReply(contactId: String) async throws -> NeedsYouDraft {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/needs-you").appending(path: contactId).appending(path: "draft")
        let data = try await authorizedRequest(method: "POST", url: url, body: Data("{}".utf8))
        return try decoder.decode(NeedsYouDraftEnvelope.self, from: data).data
    }

    func sendNeedsYouReply(contactId: String, subject: String, body: String) async throws {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/needs-you").appending(path: contactId).appending(path: "send")
        _ = try await authorizedRequest(method: "POST", url: url, body: try encoder.encode(NeedsYouSendRequest(subject: subject, body: body)))
    }

    func markNeedsYouDone(contactId: String) async throws {
        let url = config.apiBaseURL.appending(path: "mobile/outreach/needs-you").appending(path: contactId).appending(path: "done")
        _ = try await authorizedRequest(method: "POST", url: url, body: Data("{}".utf8))
    }

    // MARK: - Push notifications and activity (pushRoutes.js)

    func registerPushDevice(token: String, environment: String, appVersion: String) async throws {
        let url = config.apiBaseURL.appending(path: "mobile/push/devices")
        let body = try encoder.encode(PushDeviceRequest(token: token, app: "outreach", environment: environment, appVersion: appVersion))
        _ = try await authorizedRequest(method: "POST", url: url, body: body)
    }

    func unregisterPushDevice(token: String) async throws {
        let url = config.apiBaseURL.appending(path: "mobile/push/devices").appending(path: token)
        _ = try await authorizedRequest(method: "DELETE", url: url)
    }

    func fetchPushPreferences() async throws -> PushPreferences {
        var components = URLComponents(url: config.apiBaseURL.appending(path: "mobile/push/preferences"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "app", value: "outreach")]
        let data = try await authorizedRequest(method: "GET", url: components.url!)
        return try decoder.decode(PushPreferencesEnvelope.self, from: data).preferences
    }

    func savePushPreferences(_ preferences: PushPreferences) async throws -> PushPreferences {
        let url = config.apiBaseURL.appending(path: "mobile/push/preferences")
        let body = try encoder.encode(PushPreferencesRequest(app: "outreach", preferences: preferences))
        let data = try await authorizedRequest(method: "PUT", url: url, body: body)
        return try decoder.decode(PushPreferencesEnvelope.self, from: data).preferences
    }

    func fetchActivity(limit: Int = 50) async throws -> [ActivityItem] {
        var components = URLComponents(url: config.apiBaseURL.appending(path: "mobile/activity"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "app", value: "outreach"), URLQueryItem(name: "limit", value: String(limit))]
        let data = try await authorizedRequest(method: "GET", url: components.url!)
        return try decoder.decode(ActivityEnvelope.self, from: data).items
    }

    // MARK: - Request building

    private func authorizedRequest(method: String, url: URL, body: Data? = nil) async throws -> Data {
        let idToken = try await authService.freshIdToken()

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutreachAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let message = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.displayText, !message.isEmpty {
                throw OutreachAPIError.server(httpResponse.statusCode, message)
            }
            throw OutreachAPIError.httpError(httpResponse.statusCode)
        }

        return data
    }
}
