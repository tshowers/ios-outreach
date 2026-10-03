import Foundation

/// Where the Send tab is in a batch.
enum CatalystPhase: Equatable {
    case idle
    case drafting(CatalystContact)
    /// Paused on one email until you send or skip it (Auto sends it).
    case preview(CatalystContact)
    case sending(CatalystContact)
    case finished
}

/// Web Catalyst's emailer (email-processor + emailer.component.ts) for iOS,
/// without the pasted-template mode: pick how many of the stalest contacts
/// to email, then Maya drafts each one from the contact's relationship tip,
/// the queue pauses on every preview, and each batch is a run in History.
/// The queue runs on the phone, as it runs in the browser on the web - Auto
/// keeps going only while the app is open.
@MainActor
final class CatalystStore: ObservableObject {
    static let maxBatch = 500

    @Published private(set) var queue: [CatalystContact] = []
    @Published private(set) var status: CatalystSendingStatus?
    @Published private(set) var runs: [CatalystRun] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false

    @Published var batchSize: Int {
        didSet { UserDefaults.standard.set(batchSize, forKey: Self.batchSizeKey) }
    }
    @Published private(set) var autoRun = false
    @Published var tone: CatalystTone = .direct

    @Published private(set) var phase: CatalystPhase = .idle
    @Published var subject = ""
    @Published var message = ""
    @Published private(set) var pending: [CatalystContact] = []
    @Published private(set) var skipped: [CatalystContact] = []
    @Published private(set) var totalCount = 0
    @Published private(set) var sentCount = 0
    @Published var errorMessage: String?
    @Published var notice: String?

    /// Called after each real send, e.g. to check awards.
    var onSent: (() -> Void)?

    private let apiClient: OutreachAPIClient
    private static let batchSizeKey = "catalyst.batchSize"
    /// The batch as it was when Start was tapped - what Reload Queue replays.
    private var initialSnapshot: [CatalystContact] = []
    private var sentIds: Set<String> = []
    private var runId: String?
    /// Bumped by Start and Stop so a draft that comes back late is ignored.
    private var generation = 0
    #if DEBUG
    /// DesignGallery's sample store never reaches the network.
    private var isSample = false
    #endif

    init(apiClient: OutreachAPIClient) {
        self.apiClient = apiClient
        let saved = UserDefaults.standard.integer(forKey: Self.batchSizeKey)
        batchSize = saved > 0 ? min(saved, Self.maxBatch) : 25
    }

    // MARK: - Stale Contacts

    /// The contacts the next Start will email, stalest first.
    var batch: [CatalystContact] { Array(queue.prefix(max(1, batchSize))) }
    var oldestGap: Int { batch.first?.daysSinceLastContact ?? 0 }
    var averageGap: Int {
        guard !batch.isEmpty else { return 0 }
        return Int((Double(batch.reduce(0) { $0 + $1.daysSinceLastContact }) / Double(batch.count)).rounded())
    }
    var urgentBacklog: Int { batch.filter { $0.daysSinceLastContact >= 30 }.count }
    /// The most you can pick: everyone waiting, up to 500.
    var batchLimit: Int { max(1, min(Self.maxBatch, queue.count)) }

    // MARK: - Send

    var isRunning: Bool {
        switch phase {
        case .drafting, .preview, .sending: return true
        case .idle, .finished: return false
        }
    }

    var currentContact: CatalystContact? {
        switch phase {
        case .drafting(let contact), .preview(let contact), .sending(let contact): return contact
        case .idle, .finished: return nil
        }
    }

    var remainingCount: Int { pending.count + (currentContact == nil ? 0 : 1) }
    var canStart: Bool { !isRunning && !batch.isEmpty }
    var canLoadSkipped: Bool { !isRunning && !skipped.isEmpty }
    var canReload: Bool { !isRunning && initialSnapshot.contains { !sentIds.contains($0.id) } }

    func load() async {
        #if DEBUG
        if isSample { return }
        #endif
        isLoading = true
        async let queueResult = apiClient.fetchCatalystQueue(limit: Self.maxBatch)
        async let statusResult = apiClient.fetchCatalystSendingStatus()
        async let runsResult = apiClient.fetchCatalystRuns()
        do {
            queue = try await queueResult
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        status = try? await statusResult
        if let loaded = try? await runsResult { runs = loaded }
        isLoading = false
        hasLoaded = true
    }

    func refreshHistory() async {
        #if DEBUG
        if isSample { return }
        #endif
        do {
            runs = try await apiClient.fetchCatalystRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() async {
        guard canStart else { return }
        let contacts = batch
        generation += 1
        let current = generation
        initialSnapshot = contacts
        sentIds = []
        pending = contacts
        skipped = []
        totalCount = contacts.count
        sentCount = 0
        errorMessage = nil
        notice = nil
        // History is a nice-to-have; the batch still runs if this fails, as on the web.
        runId = try? await apiClient.createCatalystRun(contactIds: contacts.map(\.id)).id
        await runQueue(current)
    }

    func stop() {
        guard isRunning else { return }
        generation += 1
        pending = []
        phase = .idle
        notice = "Stopped. \(sentCount) sent."
        Task { await finalizeRun("stopped") }
    }

    func reloadQueue() async {
        guard canReload else { return }
        generation += 1
        pending = initialSnapshot.filter { !sentIds.contains($0.id) }
        skipped = []
        notice = nil
        await runQueue(generation)
    }

    func loadSkipped() async {
        guard canLoadSkipped else { return }
        generation += 1
        pending = skipped
        skipped = []
        notice = nil
        await runQueue(generation)
    }

    /// Turning Auto on while an email is waiting sends it and carries on.
    func setAutoRun(_ isOn: Bool) {
        autoRun = isOn
        if isOn, case .preview = phase {
            Task { await sendCurrent() }
        }
    }

    func sendCurrent() async {
        guard case .preview(let contact) = phase else { return }
        let current = generation
        if await deliver(contact) {
            await runQueue(current)
        }
    }

    func skipCurrent() async {
        guard case .preview(let contact) = phase else { return }
        skipped.append(contact)
        await runQueue(generation)
    }

    func redraft() async {
        guard case .preview(let contact) = phase else { return }
        let current = generation
        phase = .drafting(contact)
        do {
            try await draft(contact)
        } catch {
            errorMessage = error.localizedDescription
        }
        guard current == generation else { return }
        phase = .preview(contact)
    }

    func sendTest() async {
        guard case .preview(let contact) = phase else { return }
        do {
            try await apiClient.sendCatalystTest(contactId: contact.id, subject: subject, html: CatalystText.html(fromPlainText: message))
            notice = "Test sent to you."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drafts the next contact and pauses on its preview - or, with Auto on,
    /// sends it and keeps going until the batch is done.
    private func runQueue(_ current: Int) async {
        while current == generation, !pending.isEmpty {
            let contact = pending.removeFirst()
            phase = .drafting(contact)
            do {
                try await draft(contact)
            } catch {
                guard current == generation else { return }
                skipped.append(contact)
                notice = "Skipped \(contact.firstName): \(error.localizedDescription)"
                continue
            }
            guard current == generation else { return }
            phase = .preview(contact)
            guard autoRun else { return }
            guard await deliver(contact) else {
                // Leave the failed email on screen and stop sending on our own.
                autoRun = false
                return
            }
        }
        guard current == generation, pending.isEmpty else { return }
        phase = .finished
        await finalizeRun("completed")
    }

    private func draft(_ contact: CatalystContact) async throws {
        let draft = try await apiClient.draftCatalystEmail(contactId: contact.id, tone: tone)
        subject = draft.subject
        message = CatalystText.plainText(fromHTML: draft.bodyHtml)
    }

    private func deliver(_ contact: CatalystContact) async -> Bool {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespaces)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty, !trimmedMessage.isEmpty else {
            errorMessage = "Add a subject and a message before sending."
            return false
        }
        phase = .sending(contact)
        errorMessage = nil
        do {
            _ = try await apiClient.sendCatalystEmail(
                contactId: contact.id,
                subject: trimmedSubject,
                html: CatalystText.html(fromPlainText: trimmedMessage),
                runId: runId
            )
            sentCount += 1
            sentIds.insert(contact.id)
            queue.removeAll { $0.id == contact.id }
            onSent?()
            return true
        } catch {
            errorMessage = error.localizedDescription
            if phase == .sending(contact) { phase = .preview(contact) }
            return false
        }
    }

    private func finalizeRun(_ status: String) async {
        if let runId {
            try? await apiClient.finalizeCatalystRun(id: runId, status: status, queuedCount: initialSnapshot.count, skippedCount: skipped.count)
        }
        self.status = (try? await apiClient.fetchCatalystSendingStatus()) ?? self.status
        await refreshHistory()
    }
}

#if DEBUG
extension CatalystStore {
    /// Sample data for DesignGallery - no network.
    func loadSample(queue: [CatalystContact], status: CatalystSendingStatus, runs: [CatalystRun], previewing: Bool = false) {
        isSample = true
        self.queue = queue
        self.status = status
        self.runs = runs
        hasLoaded = true
        guard previewing, let first = queue.first else { return }
        totalCount = 25
        sentCount = 3
        pending = Array(queue.dropFirst().prefix(21))
        subject = "How construction teams stay on schedule"
        message = "Hi \(first.firstName),\n\nWhen crews feel out of the loop, small delays add up fast. I've seen a few teams fix that with a five-minute daily check-in.\n\nWould a short call next week be useful?\n\nTy"
        phase = .preview(first)
    }
}
#endif

