import SwiftUI
import TODDAwardsKit
import TODDProfileKit

enum AccountPage: Hashable {
    case gettingStarted, profile, awards, notifications
}

/// Full-screen account area (like Outreach's Status
/// screens) with its own NavigationStack, so Getting Started, Profile and
/// Awards are pushed pages with back buttons - never sheets. Opening it
/// from the menu pushes the chosen page straight away; Back lands on this
/// list, Done returns to the dashboard.
struct AccountView: View {
    let authService: AuthService
    let apiClient: OutreachAPIClient
    @ObservedObject var awardsService: AwardsService
    let onOpenWeb: (_ path: String, _ host: URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [AccountPage]

    static let outreachHost = URL(string: "https://outreach.taliferro.tech")!
    static let toddHost = URL(string: "https://todd.taliferro.tech")!
    static let showAtStartupKey = "outreach.gettingStarted.showAtStartup"

    init(start: AccountPage?, authService: AuthService, apiClient: OutreachAPIClient, awardsService: AwardsService, onOpenWeb: @escaping (_ path: String, _ host: URL) -> Void) {
        self.authService = authService
        self.apiClient = apiClient
        self.awardsService = awardsService
        self.onOpenWeb = onOpenWeb
        _path = State(initialValue: start.map { [$0] } ?? [])
    }

    static func gettingStartedAPI(authService: AuthService) -> GettingStartedAPI {
        GettingStartedAPI(
            baseURL: AppConfig.fromBundle().apiBaseURL,
            path: "getting-started/outreach",
            idToken: { @MainActor [weak authService] in
                guard let authService else { throw AuthServiceError.notSignedIn }
                return try await authService.freshIdToken()
            }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink(value: AccountPage.gettingStarted) {
                    Label("Getting Started", systemImage: "checklist")
                }
                NavigationLink(value: AccountPage.profile) {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                NavigationLink(value: AccountPage.awards) {
                    Label("Awards", systemImage: "rosette")
                }
                NavigationLink(value: AccountPage.notifications) {
                    Label("Notifications", systemImage: "bell.badge")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: AccountPage.self) { page in
                switch page {
                case .gettingStarted: gettingStartedView
                case .profile: profileView
                case .awards:
                    AwardsGridView(awardsService: awardsService)
                        .task { await awardsService.sync() }
                case .notifications:
                    NotificationSettingsView(apiClient: apiClient)
                }
            }
        }
    }

    private var gettingStartedView: some View {
        GettingStartedView(
            api: Self.gettingStartedAPI(authService: authService),
            appName: "Outreach",
            accent: OutreachTheme.accent,
            showAtStartupKey: Self.showAtStartupKey,
            destination: { stepId in
                stepId == "profile" ? AnyView(profileView) : nil
            },
            onSelect: { stepId in
                // Inbox, campaigns and sending live on the web app.
                switch stepId {
                case "connectInbox": onOpenWeb("/inbox-access", Self.outreachHost)
                case "firstCampaign": onOpenWeb("/signal-engine", Self.outreachHost)
                case "firstSend": onOpenWeb("/compose-email", Self.outreachHost)
                default: break
                }
            }
        )
    }

    /// The shared in-app profile screen (TODDProfileKit) - also where the
    /// App Store-required "Delete account" lives.
    private var profileView: some View {
        let authService = self.authService
        return ProfileView(
            api: ProfileAPI(
                baseURL: AppConfig.fromBundle().apiBaseURL,
                idToken: { @MainActor [weak authService] in
                    guard let authService else { throw AuthServiceError.notSignedIn }
                    return try await authService.freshIdToken()
                }
            ),
            appName: "Outreach",
            accent: OutreachTheme.accent,
            onOpenWebSettings: { onOpenWeb("/update-profile", Self.toddHost) },
            onAccountDeleted: {
                AuthService.profileStore.clear()
                InboxDraft.clear()
                try? authService.signOut()
            }
        ) {
            Color(.systemGroupedBackground)
        }
    }
}
