import SwiftUI
import TODDAuthKit
import TODDAwardsKit
import TODDProfileKit

/// The default screen on login for Outreach - the one exception to the
/// "list first, Status in the menu" pattern every other app (Network,
/// Moves, Docs, Pulse) follows. Native adaptation of
/// `outreach-home.component.ts`'s cockpit dashboard: rather than
/// re-deriving `outreach-home`'s client-side symptom/gauge calculations,
/// this uses the same server-computed `SignalEngineSummary` the web app's
/// `/outreach/signal-engine/bootstrap` endpoint already returns - real
/// numbers, same source of truth, no duplicated derivation logic. Mirrors
/// network-ios's NetworkStatusView in spirit (command deck + health tiles +
/// diagnosis rows), simplified since outreach-ios has no NetworkTheme
/// equivalent yet.
struct OutreachStatusView: View {
    @StateObject private var viewModel: OutreachStatusViewModel
    @StateObject private var needsYou: NeedsYouStore
    @StateObject private var drafts: DraftsStore
    /// Owned here so a running batch survives leaving the Catalyst page.
    @StateObject private var catalyst: CatalystStore
    /// Fetched as soon as the dashboard loads, so Inbox opens with mail in it.
    @StateObject private var inbox: InboxStore
    @ObservedObject var authService: AuthService
    @ObservedObject var awardsService: AwardsService
    let apiClient: OutreachAPIClient
    @State private var isShowingMessagesSent = false
    /// Getting Started / Profile / Awards - see AccountView.
    @State private var isShowingAccount = false
    @State private var accountStart: AccountPage?
    /// The inbox picked in the pre-sign-in wizard, waiting to be connected.
    @State private var isShowingConnectInbox = false
    /// Inbox, messages and connecting are pushed pages (no sheets).
    @State private var path: [OutreachRoute] = []
    @State private var isShowingLogoutConfirmation = false
    /// The newest Activity item, for the Activity tile.
    @State private var latestActivity: ActivityItem?
    @State private var isOpeningWebHandoff = false
    @State private var webHandoffErrorMessage: String?

    private static let outreachHost = URL(string: "https://outreach.taliferro.tech")!
    private static let toddHost = URL(string: "https://todd.taliferro.tech")!

    /// Web pages reachable from the account menu via the shared
    /// `TODDAuthKit.WebHandoff` real-token handoff - opens already signed
    /// in, no second login. Profile is in-app now (AccountView).
    private static let webHandoffMenuItems: [(title: String, icon: String, path: String, host: URL)] = [
        (title: "Home", icon: "house", path: "/", host: outreachHost),
        (title: "Growth", icon: "chart.line.uptrend.xyaxis", path: "/app", host: outreachHost),
        (title: "Outbox", icon: "paperplane.circle", path: "/signal-engine", host: outreachHost),
        (title: "Email Composer", icon: "square.and.pencil", path: "/compose-email", host: outreachHost),
        (title: "Help", icon: "questionmark.circle", path: "/help", host: outreachHost),
        (title: "Daily Momentum", icon: "flame", path: "/daily-momentum", host: toddHost),
    ]

    init(apiClient: OutreachAPIClient, authService: AuthService, awardsService: AwardsService) {
        self.apiClient = apiClient
        self.authService = authService
        self.awardsService = awardsService
        _viewModel = StateObject(wrappedValue: OutreachStatusViewModel(apiClient: apiClient))
        _needsYou = StateObject(wrappedValue: NeedsYouStore(apiClient: apiClient))
        _drafts = StateObject(wrappedValue: DraftsStore(apiClient: apiClient))
        _catalyst = StateObject(wrappedValue: CatalystStore(apiClient: apiClient))
        _inbox = StateObject(wrappedValue: InboxStore(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let summary = viewModel.summary {
                    dashboard(summary)
                } else if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text(viewModel.errorMessage)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await viewModel.load()
                await needsYou.load()
                await drafts.load()
                await loadTileExtras()
            }
            .onReceive(PushService.shared.$pendingRoute) { url in
                guard let url else { return }
                PushService.shared.pendingRoute = nil
                isShowingAccount = false
                openRoute(url)
            }
            // Alongside the dashboard's own loading, not after it: reading
            // the mailbox takes a few seconds.
            .task { await inbox.prefetch() }
            .task { await loadTileExtras() }
            .task {
                await PushService.shared.registerIfAllowed()
                await needsYou.load()
                await drafts.load()
                await viewModel.load()
                await checkAwards()
                // Came through the wizard: connect that inbox first;
                // Getting Started follows once it's closed.
                if InboxDraft.load().isPendingConnect {
                    isShowingConnectInbox = true
                    return
                }
                // Open the checklist once per launch while steps remain,
                // unless the user switched it off there.
                if await GettingStartedStartup.shouldAutoShow(
                    api: AccountView.gettingStartedAPI(authService: authService),
                    showAtStartupKey: AccountView.showAtStartupKey
                ) {
                    openAccount(.gettingStarted)
                }
            }
            .fullScreenCover(isPresented: $isShowingAccount, onDismiss: {
                // Steps get done from here - the likeliest moment for new awards.
                Task { await checkAwards() }
            }) {
                AccountView(start: accountStart, authService: authService, apiClient: apiClient, awardsService: awardsService) { path, host in
                    openWebHandoff(path: path, host: host)
                }
            }
            .fullScreenCover(isPresented: $isShowingConnectInbox) {
                ConnectInboxView(
                    onConnect: { draft in
                        // Connect in the app: Inbox, then the connect page
                        // pre-filled with the wizard's address.
                        path = [.inbox, .connect(email: draft.trimmedEmail, provider: draft.provider)]
                    },
                    onFinished: { isShowingConnectInbox = false }
                )
            }
            .navigationDestination(for: OutreachRoute.self) { route in
                switch route {
                case .inbox:
                    InboxView(store: inbox, defaultEmail: authService.userEmail ?? "", path: $path)
                case .message(let mailboxId, let messageId):
                    MessageDetailView(apiClient: apiClient, mailboxId: mailboxId, messageId: messageId)
                case .catalyst:
                    CatalystView(store: catalyst)
                        .onAppear { catalyst.onSent = { Task { await checkAwards() } } }
                case .activity:
                    ActivityView(apiClient: apiClient) { url in openRoute(url) }
                case .needsYou:
                    NeedsYouView(store: needsYou, path: $path)
                case .needsYouDetail(let item):
                    NeedsYouDetailView(item: item, store: needsYou, path: $path)
                case .needsYouReply(let item, let useMayaDraft):
                    NeedsYouReplyView(item: item, useMayaDraft: useMayaDraft, store: needsYou, path: $path)
                case .drafts:
                    DraftsView(store: drafts, path: $path)
                case .draftDetail(let item):
                    DraftDetailView(item: item, store: drafts, path: $path)
                case .connect(let email, let provider):
                    ConnectMailboxView(apiClient: apiClient, email: email, provider: provider) {
                        Task { await checkAwards() }
                        Task { await inbox.load() }
                        // Back to the inbox, which reloads and shows it.
                        Task {
                            try? await Task.sleep(for: .milliseconds(900))
                            if path.last != .inbox { path = [.inbox] }
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingMessagesSent) {
                EmailActivityListView(apiClient: apiClient)
            }
            .alert("Log out of Outreach?", isPresented: $isShowingLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    Task {
                        await PushService.shared.unregister()
                        try? authService.signOut()
                    }
                }
            } message: {
                Text("You can sign in again with your TODD account.")
            }
            .alert("Couldn't open that page", isPresented: .constant(webHandoffErrorMessage != nil)) {
                Button("OK") { webHandoffErrorMessage = nil }
            } message: {
                Text(webHandoffErrorMessage ?? "")
            }
        }
    }

    /// Opens the page a tapped notification (or Activity row) points to.
    private func openRoute(_ url: URL) {
        guard url.scheme == "outreach" else { return }
        switch url.host() {
        case "needs-you":
            // outreach://needs-you/<contactId> opens that person.
            let contactId = url.pathComponents.dropFirst().first ?? ""
            Task {
                await needsYou.load()
                if let item = needsYou.item(for: contactId) {
                    path = [.needsYou, .needsYouDetail(item)]
                } else {
                    path = [.needsYou]
                }
            }
        case "inbox": path = [.inbox]
        case "drafts": path = [.drafts]
        // Maya's day summary lives on the web for now (Maya's app gets a
        // native one in its 1.1).
        case "maya-day": openWebHandoff(path: "/maya-day", host: Self.outreachHost)
        case "catalyst": path = [.catalyst]
        case "activity": path = [.activity]
        case "notifications": openAccount(.notifications)
        default: path = [.activity]
        }
    }

    /// Catalyst's waiting count and the newest Activity item for the tiles.
    private func loadTileExtras() async {
        async let activity = try? apiClient.fetchActivity(limit: 1)
        if !catalyst.isRunning { await catalyst.load() }
        latestActivity = await activity?.first
    }

    private func openAccount(_ page: AccountPage?) {
        accountStart = page
        isShowingAccount = true
    }

    private func checkAwards() async {
        if let progress = try? await apiClient.fetchProgress() {
            awardsService.recordProgress(progress)
        }
    }

    /// Opens a web page already signed in via the shared
    /// `TODDAuthKit.WebHandoff` real-token handoff - no second login.
    private func openWebHandoff(path: String, host: URL) {
        isOpeningWebHandoff = true
        Task {
            defer { isOpeningWebHandoff = false }
            do {
                let idToken = try await authService.freshIdToken()
                try await WebHandoff.open(
                    path: path,
                    idToken: idToken,
                    apiBaseURL: AppConfig.fromBundle().apiBaseURL,
                    webBaseURL: host
                )
            } catch {
                webHandoffErrorMessage = "Please try again in a moment."
            }
        }
    }

    // MARK: - Home (design 4a)

    private func dashboard(_ summary: SignalEngineSummary) -> some View {
        HomeDashboard(
            model: HomeModel(
                userName: authService.currentUser?.displayName ?? authService.userEmail ?? "You",
                brokenMailbox: brokenMailbox?.emailAddress,
                needsYouNames: needsYou.hasLoaded ? needsYou.items.map(\.contactName) : nil,
                draftsCount: drafts.hasLoaded ? drafts.items.count : nil,
                draftsDetail: drafts.items.isEmpty && drafts.rewritingCount > 0 ? "Maya is rewriting \(drafts.rewritingCount)" : "waiting for approval",
                inboxNewCount: inbox.messagesByMailbox.isEmpty ? nil : newInboxCount,
                catalystCount: catalyst.hasLoaded ? catalyst.queue.count : nil,
                activityDetail: latestActivity?.title ?? "What Maya and TODD did",
                summary: summary
            ),
            actions: HomeActions(
                reconnect: {
                    guard let mailbox = brokenMailbox else { return }
                    path = [.inbox, .connect(email: mailbox.emailAddress, provider: MailProvider.detect(from: mailbox.emailAddress))]
                },
                needsYou: { path = [.needsYou] },
                startNeedsYou: {
                    if let first = needsYou.items.first { path = [.needsYou, .needsYouDetail(first)] }
                },
                // Straight into review, one at a time; "See list" goes back.
                drafts: { path = drafts.items.first.map { [.drafts, .draftDetail($0)] } ?? [.drafts] },
                inbox: { path = [.inbox] },
                catalyst: { path = [.catalyst] },
                activity: { path = [.activity] }
            )
        ) {
            accountMenuItems
        } footer: {
            NotificationsPromptCard()
        }
    }

    @ViewBuilder
    private var accountMenuItems: some View {
        // In-app pages first; web pages grouped under their
        // own header so it's clear which ones leave the app.
        Button {
            path = [.needsYou]
        } label: {
            Label("Needs You", systemImage: "person.crop.circle.badge.exclamationmark")
        }
        Button {
            path = [.drafts]
        } label: {
            Label("Drafts", systemImage: "square.and.pencil")
        }
        Button {
            path = [.inbox]
        } label: {
            Label("Inbox", systemImage: "tray")
        }
        Button {
            path = [.catalyst]
        } label: {
            Label("Catalyst", systemImage: "bolt.badge.clock")
        }
        Button {
            path = [.activity]
        } label: {
            Label("Activity", systemImage: "bell")
        }
        Button {
            openAccount(.gettingStarted)
        } label: {
            Label("Getting Started", systemImage: "checklist")
        }
        Button {
            openAccount(.profile)
        } label: {
            Label("Profile", systemImage: "person.crop.circle")
        }
        Button {
            openAccount(.awards)
        } label: {
            Label("Awards", systemImage: "rosette")
        }
        Button {
            openAccount(.notifications)
        } label: {
            Label("Notifications", systemImage: "bell.badge")
        }
        Button {
            isShowingMessagesSent = true
        } label: {
            Label("Messages Sent", systemImage: "paperplane")
        }
        Section("Opens outreach.taliferro.tech") {
            ForEach(Self.webHandoffMenuItems, id: \.title) { item in
                Button {
                    openWebHandoff(path: item.path, host: item.host)
                } label: {
                    Label(item.title, systemImage: item.icon)
                }
                .disabled(isOpeningWebHandoff)
            }
        }
        Section {
            Button(role: .destructive) {
                isShowingLogoutConfirmation = true
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    /// An inbox the last sync couldn't reach.
    private var brokenMailbox: MailboxSummary? {
        inbox.mailboxes.first { $0.lastSyncStatus == "failed" }
    }

    /// Messages that arrived today in the inbox Outreach shows.
    private var newInboxCount: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return inbox.messages.filter { ($0.receivedDate ?? .distantPast) >= startOfDay }.count
    }
}
