import Foundation
import UserNotifications

/// The Needs You list, shared by the dashboard card, the list, the
/// conversation page and the reply page - so a reply sent or a "Done"
/// anywhere drops the person everywhere, and the app icon badge follows.
@MainActor
final class NeedsYouStore: ObservableObject {
    @Published private(set) var items: [NeedsYouItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let apiClient: OutreachAPIClient
    #if DEBUG
    /// DesignGallery's sample store never reaches the network.
    private var isSample = false
    #endif

    init(apiClient: OutreachAPIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        #if DEBUG
        if isSample { return }
        #endif
        isLoading = true
        do {
            items = try await apiClient.fetchNeedsYou()
            errorMessage = nil
            updateBadge()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }

    func item(for contactId: String) -> NeedsYouItem? {
        items.first { $0.contactId == contactId }
    }

    func draftReply(for item: NeedsYouItem) async throws -> NeedsYouDraft {
        try await apiClient.draftNeedsYouReply(contactId: item.contactId)
    }

    func sendReply(to item: NeedsYouItem, subject: String, body: String) async throws {
        try await apiClient.sendNeedsYouReply(contactId: item.contactId, subject: subject, body: body)
        remove(item)
    }

    func markDone(_ item: NeedsYouItem) async throws {
        try await apiClient.markNeedsYouDone(contactId: item.contactId)
        remove(item)
    }

    private func remove(_ item: NeedsYouItem) {
        items.removeAll { $0.contactId == item.contactId }
        updateBadge()
    }

    private func updateBadge() {
        UNUserNotificationCenter.current().setBadgeCount(items.count)
    }
}

#if DEBUG
extension NeedsYouStore {
    func loadSample(_ items: [NeedsYouItem]) {
        isSample = true
        self.items = items
        hasLoaded = true
    }
}
#endif
