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
    /// Maya's own conversations (Plan), for the "nobody's waiting" screen.
    @Published var planCount: Int?
    /// "Marked Dana done · Undo" - the done call waits until it goes.
    @Published private(set) var toast: (text: String, canUndo: Bool)?
    private var pendingDone: [NeedsYouItem] = []
    private var pendingTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

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
            let pendingIds = Set(pendingDone.map(\.contactId))
            items = try await apiClient.fetchNeedsYou().filter { !pendingIds.contains($0.contactId) }
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

    var answerItems: [NeedsYouItem] { items.filter(\.needsAnswer) }
    var clearItems: [NeedsYouItem] { items.filter { !$0.needsAnswer } }

    /// Needs an answer first, then newest reply first (design 5a).
    var ordered: [NeedsYouItem] { answerItems + clearItems }

    /// Done, with five seconds to undo before it reaches the server.
    func markDoneWithUndo(_ done: [NeedsYouItem]) {
        guard !done.isEmpty else { return }
        commitPendingDone()
        pendingDone = done
        let ids = Set(done.map(\.contactId))
        items.removeAll { ids.contains($0.contactId) }
        updateBadge()
        showToast(done.count == 1 ? "Marked \(done[0].contactName) done" : "Marked \(done.count) done", canUndo: true)
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.commitPendingDone()
        }
    }

    func undo() {
        guard !pendingDone.isEmpty else { return }
        pendingTask?.cancel()
        items = sortedByReply(items + pendingDone)
        pendingDone = []
        toast = nil
        updateBadge()
    }

    /// Sends any done that's still waiting on its Undo - e.g. on leaving.
    func commitPendingDone() {
        pendingTask?.cancel()
        let done = pendingDone
        pendingDone = []
        #if DEBUG
        if isSample { return }
        #endif
        for item in done {
            Task {
                do {
                    try await apiClient.markNeedsYouDone(contactId: item.contactId)
                } catch {
                    // Didn't go through: put them back rather than lose them.
                    items = sortedByReply(items + [item])
                    updateBadge()
                    showToast("Couldn't mark \(item.contactName) done", canUndo: false)
                }
            }
        }
    }

    func showToast(_ text: String, canUndo: Bool) {
        toastTask?.cancel()
        toast = (text, canUndo)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func sortedByReply(_ list: [NeedsYouItem]) -> [NeedsYouItem] {
        list.sorted { $0.repliedAt > $1.repliedAt }
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
