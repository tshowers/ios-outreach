import Foundation

/// The connected inboxes and their recent messages, kept for the session so
/// the Inbox opens on the last messages it saw (as Mail does) and refreshes
/// behind them. Loading messages means the server reads the mailbox live
/// over IMAP, which takes a few seconds - the dashboard starts that early
/// with `prefetch()`. Memory only: nothing from the mailbox is written to disk.
@MainActor
final class InboxStore: ObservableObject {
    @Published private(set) var mailboxes: [MailboxSummary] = []
    @Published var selectedMailboxId: String?
    @Published private(set) var messagesByMailbox: [String: [MailboxMessage]] = [:]
    /// Mailboxes being fetched right now.
    @Published private(set) var loadingMailboxIds: Set<String> = []
    @Published private(set) var hasLoadedMailboxes = false
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?

    private let apiClient: OutreachAPIClient
    private var lastRefresh: Date?

    init(apiClient: OutreachAPIClient) {
        self.apiClient = apiClient
    }

    var selectedMailbox: MailboxSummary? {
        mailboxes.first { $0.id == selectedMailboxId } ?? mailboxes.first
    }

    var messages: [MailboxMessage] {
        selectedMailbox.flatMap { messagesByMailbox[$0.id] } ?? []
    }

    /// No messages for this inbox yet, and they're on the way.
    var isLoadingFirstMessages: Bool {
        guard let id = selectedMailbox?.id else { return !hasLoadedMailboxes }
        return messagesByMailbox[id] == nil && (loadingMailboxIds.contains(id) || !hasLoadedMailboxes)
    }

    var isRefreshing: Bool {
        guard let id = selectedMailbox?.id else { return false }
        return messagesByMailbox[id] != nil && loadingMailboxIds.contains(id)
    }

    /// Warms the inbox from the dashboard so it's ready before it's opened.
    func prefetch() async {
        guard !hasLoadedMailboxes else { return }
        await load()
    }

    /// Opening the Inbox: show what's here, refresh unless it's fresh.
    func refreshIfStale() async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60, !messages.isEmpty { return }
        await load()
    }

    func load() async {
        do {
            mailboxes = try await apiClient.fetchMailboxes()
            if selectedMailboxId == nil || !mailboxes.contains(where: { $0.id == selectedMailboxId }) {
                selectedMailboxId = (mailboxes.first { $0.isPrimary == true } ?? mailboxes.first)?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoadedMailboxes = true
        await loadMessages()
    }

    func select(_ mailboxId: String) async {
        selectedMailboxId = mailboxId
        await loadMessages()
    }

    func loadMessages() async {
        guard let id = selectedMailbox?.id, !loadingMailboxIds.contains(id) else { return }
        loadingMailboxIds.insert(id)
        defer { loadingMailboxIds.remove(id) }
        do {
            messagesByMailbox[id] = try await apiClient.fetchMessages(mailboxId: id)
            lastRefresh = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sync() async {
        guard let id = selectedMailbox?.id else { await load(); return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await apiClient.syncMailbox(mailboxId: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
    }

    func makePrimary(_ mailbox: MailboxSummary) async {
        do {
            try await apiClient.setPrimaryMailbox(mailboxId: mailbox.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        guard let id = selectedMailbox?.id else { return }
        do {
            try await apiClient.disconnectMailbox(mailboxId: id)
            selectedMailboxId = nil
            messagesByMailbox[id] = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
