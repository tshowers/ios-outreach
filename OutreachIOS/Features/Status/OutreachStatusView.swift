import SwiftUI
import TODDAuthKit

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
    let apiClient: OutreachAPIClient
    @State private var isShowingMessagesSent = false
    @State private var isShowingLogoutConfirmation = false
    @State private var isOpeningWebHandoff = false
    @State private var webHandoffErrorMessage: String?

    private static let outreachHost = URL(string: "https://outreach.taliferro.tech")!
    private static let toddHost = URL(string: "https://todd.taliferro.tech")!

    /// Every destination reachable from Outreach's account menu via the
    /// shared `TODDAuthKit.WebHandoff` real-token handoff - opens already
    /// signed in, no second login. Mixes both taliferro.tech domains since
    /// the handoff works across any custom domain on the same Firebase
    /// project (the custom token isn't domain-scoped).
    private static let webHandoffMenuItems: [(title: String, icon: String, path: String, host: URL)] = [
        (title: "Home", icon: "house", path: "/", host: outreachHost),
        (title: "Growth", icon: "chart.line.uptrend.xyaxis", path: "/app", host: outreachHost),
        (title: "Inbox", icon: "tray", path: "/inbox-access", host: outreachHost),
        (title: "Outbox", icon: "paperplane.circle", path: "/signal-engine", host: outreachHost),
        (title: "Catalyst", icon: "bolt.badge.clock", path: "/email-processor", host: outreachHost),
        (title: "Email Composer", icon: "square.and.pencil", path: "/compose-email", host: outreachHost),
        (title: "Daily Momentum", icon: "flame", path: "/daily-momentum", host: toddHost),
        (title: "Profile", icon: "person.crop.circle", path: "/user-profile", host: toddHost),
        (title: "Help", icon: "questionmark.circle", path: "/help", host: toddHost),
    ]

    init(apiClient: OutreachAPIClient, authService: AuthService) {
        self.apiClient = apiClient
        self.authService = authService
        _viewModel = StateObject(wrappedValue: OutreachStatusViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
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
                        ForEach(Self.webHandoffMenuItems, id: \.title) { item in
                            Button {
                                openWebHandoff(path: item.path, host: item.host)
                            } label: {
                                Label(item.title, systemImage: item.icon)
                            }
                            .disabled(isOpeningWebHandoff)
                        }
                        Divider()
                        Button {
                            isShowingMessagesSent = true
                        } label: {
                            Label("Messages Sent", systemImage: "paperplane")
                        }
                        Button(role: .destructive) {
                            isShowingLogoutConfirmation = true
                        } label: {
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Label("Account", systemImage: "person.crop.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Account menu")
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .sheet(isPresented: $isShowingMessagesSent) {
                EmailActivityListView(apiClient: apiClient)
            }
            .alert("Log out of Outreach?", isPresented: $isShowingLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    try? authService.signOut()
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
