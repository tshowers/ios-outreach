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
    /// Contacts emailed from Catalyst this session - hidden from its queue.
    @State private var catalystSentIds: Set<String> = []
    @State private var isShowingLogoutConfirmation = false
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // In-app pages first; web pages grouped under their
                        // own header so it's clear which ones leave the app.
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
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Account menu")
                }
            }
            .refreshable { await viewModel.load() }
            .onReceive(PushService.shared.$pendingRoute) { url in
                guard let url else { return }
                PushService.shared.pendingRoute = nil
                isShowingAccount = false
                openRoute(url)
            }
            .task {
                await PushService.shared.registerIfAllowed()
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
                    InboxView(apiClient: apiClient, defaultEmail: authService.userEmail ?? "", path: $path)
                case .message(let mailboxId, let messageId):
                    MessageDetailView(apiClient: apiClient, mailboxId: mailboxId, messageId: messageId)
                case .catalyst:
                    CatalystView(apiClient: apiClient, path: $path, sentContactIds: $catalystSentIds)
                case .activity:
                    ActivityView(apiClient: apiClient) { url in openRoute(url) }
                case .catalystCompose(let contact):
                    CatalystComposeView(apiClient: apiClient, contact: contact) { contactId in
                        catalystSentIds.insert(contactId)
                        Task { await checkAwards() }
                    }
                case .connect(let email, let provider):
                    ConnectMailboxView(apiClient: apiClient, email: email, provider: provider) {
                        Task { await checkAwards() }
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
    /// Needs You and Drafts get their own pages later in 1.1; until then a
    /// reply opens the Inbox.
    private func openRoute(_ url: URL) {
        guard url.scheme == "outreach" else { return }
        switch url.host() {
        case "needs-you", "inbox": path = [.inbox]
        case "catalyst": path = [.catalyst]
        case "activity": path = [.activity]
        case "notifications": openAccount(.notifications)
        default: path = [.activity]
        }
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

    private func dashboard(_ summary: SignalEngineSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                commandDeck(summary)

                NotificationsPromptCard()

                Button {
                    path = [.inbox]
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "tray.full.fill")
                            .font(.title2)
                            .foregroundStyle(OutreachTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Inbox").font(.headline)
                            Text("See who replied, read it, and answer from your own email.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    path = [.catalyst]
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bolt.badge.clock.fill")
                            .font(.title2)
                            .foregroundStyle(OutreachTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Catalyst").font(.headline)
                            Text("Reach the people who've gone quiet. TODD drafts it, you send it.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)

                panel("Pipeline") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        healthTile("bolt.fill", "Active Threads", summary.activeThreads, .blue)
                        healthTile("flame.fill", "Hot Leads", summary.hotLeads, .red)
                        healthTile("sun.max.fill", "Warm Leads", summary.warmLeads, .orange)
                        healthTile("doc.text.fill", "Draft Ready", summary.draftReady, .purple)
                        healthTile("paperplane.fill", "Queued to Send", summary.queuedActions, .green)
                        healthTile("hourglass", "Stalled / Waiting", summary.stalledWaiting, .gray)
                    }
                }

                panel("Needs a decision") {
                    diagnosisRow(
                        summary.needsHuman > 0 ? "Threads need your decision" : "Nothing needs you right now",
                        value: summary.needsHuman,
                        detail: summary.needsHuman > 0 ? "have reply or handoff signals waiting" : "TODD is watching and will surface anything that needs you",
                        tone: summary.needsHuman > 0 ? .orange : .green
                    )
                }
            }
            .padding(20)
        }
    }

    private func commandDeck(_ summary: SignalEngineSummary) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("TODD COMMAND DECK")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.blue)
                Text("Outreach")
                    .font(.largeTitle.weight(.bold))
                Text("Watch opens, clicks, and replies, and see where TODD should push next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 4) {
                Text("SENDING NOW")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text("\(summary.sending)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
            }
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func healthTile(_ icon: String, _ title: String, _ value: Int, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent)
            Text("\(value)").font(.system(size: 28, weight: .bold, design: .rounded))
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func diagnosisRow(_ title: String, value: Int, detail: String, tone: Color) -> some View {
        HStack(spacing: 14) {
            Circle().fill(tone).frame(width: 14, height: 14).shadow(color: tone.opacity(0.55), radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text("\(value) \(detail)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
