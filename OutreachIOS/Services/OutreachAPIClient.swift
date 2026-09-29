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

    private func mailboxURL(_ components: String...) -> URL {
        components.reduce(config.apiBaseURL.appending(path: "mobile/outreach/mailboxes")) { url, component in
            url.appending(path: component)
        }
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
            if let message = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.message, !message.isEmpty {
                throw OutreachAPIError.server(httpResponse.statusCode, message)
            }
            throw OutreachAPIError.httpError(httpResponse.statusCode)
        }

        return data
    }
}
