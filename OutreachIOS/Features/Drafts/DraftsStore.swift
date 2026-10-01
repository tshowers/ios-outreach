import Foundation

/// Maya's drafts, shared by the dashboard card, the list and each draft's
/// page, so an approve / reject / discard anywhere updates everywhere.
@MainActor
final class DraftsStore: ObservableObject {
    @Published private(set) var items: [DraftItem] = []
    /// Drafts Maya is rewriting right now (rejected and queued).
    @Published private(set) var rewritingCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let apiClient: OutreachAPIClient
    /// The backend takes at most 100 per batch; smaller chunks keep each
    /// request well inside its timeout, as the web Signal Engine does.
    private let chunkSize = 25

    init(apiClient: OutreachAPIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        do {
            let result = try await apiClient.fetchDrafts()
            items = result.items
            rewritingCount = result.rewritingCount
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }

    func approve(_ item: DraftItem, subject: String, body: String) async throws {
        try await apiClient.approveDraft(contactId: item.contactId, subject: subject, body: body)
        remove([item.contactId])
    }

    func reject(_ item: DraftItem, reason: String) async throws {
        try await apiClient.rejectDraft(contactId: item.contactId, reason: reason)
        // Maya rewrites it right away; reload to show the new version.
        await load()
    }

    func discard(_ item: DraftItem) async throws {
        try await apiClient.discardDraft(contactId: item.contactId)
        remove([item.contactId])
    }

    func sendTest(_ item: DraftItem) async throws {
        try await apiClient.sendDraftTest(contactId: item.contactId)
    }

    /// - Returns: how many were approved.
    func approve(contactIds: [String]) async throws -> Int {
        var approved = 0
        for chunk in contactIds.chunked(into: chunkSize) {
            approved += try await apiClient.approveDrafts(contactIds: chunk)
        }
        await load()
        return approved
    }

    /// - Returns: how many Maya will rewrite.
    func rewrite(contactIds: [String]) async throws -> Int {
        var queued = 0
        for chunk in contactIds.chunked(into: chunkSize) {
            queued += try await apiClient.rewriteDrafts(contactIds: chunk)
        }
        await load()
        return queued
    }

    private func remove(_ contactIds: Set<String>) {
        items.removeAll { contactIds.contains($0.contactId) }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
