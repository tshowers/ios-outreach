import Foundation
import TODDAwardsKit

/// Outreach's awards on the shared, account-synced TODDAwardsKit - the same
/// set on iPhone and iPad, each award celebrated once (the server decides
/// what's new). Most are checked against the real counts that
/// `/getting-started/outreach` returns, so they can't drift from the data.
enum OutreachAwards {
    static let ladder: [Award] = [
        Award(id: "first-step", title: "The First Step", copy: "You picked the inbox you'll grow from.", symbol: "envelope.badge.fill"),
        Award(id: "committer", title: "The Committer", copy: "You didn't just look \u{2014} you signed up to follow through.", symbol: "checkmark.seal.fill"),
        Award(id: "introduction", title: "The Introduction", copy: "Your profile is complete. Your emails know who's sending them.", symbol: "person.text.rectangle.fill"),
        Award(id: "listener", title: "The Listener", copy: "Your inbox is connected. No reply slips past you now.", symbol: "tray.full.fill"),
        Award(id: "campaigner", title: "The Campaigner", copy: "Your first campaign. Who to reach, and what to say.", symbol: "megaphone.fill"),
        Award(id: "first-contact", title: "First Contact", copy: "Your first email is out. That's how conversations start.", symbol: "paperplane.fill"),
        Award(id: "all-set", title: "The Regular", copy: "Getting Started, finished. You know your way around.", symbol: "star.circle.fill"),
        Award(id: "follow-through", title: "Follow-Through", copy: "Twenty-five emails sent. You keep showing up.", symbol: "arrow.triangle.2.circlepath"),
        Award(id: "rainmaker", title: "The Rainmaker", copy: "Two hundred emails sent. People know your name.", symbol: "cloud.rain.fill", hidden: true),
    ]

    @MainActor
    static func makeService(authService: AuthService) -> AwardsService {
        AwardsService(
            appName: "Outreach",
            ladder: ladder,
            api: AwardsAPI(
                baseURL: AppConfig.fromBundle().apiBaseURL,
                product: "outreach",
                idToken: { @MainActor [weak authService] in
                    guard let authService else { throw AuthServiceError.notSignedIn }
                    return try await authService.freshIdToken()
                }
            )
        )
    }
}

/// Outreach's record points - each checked at the moment it could become true.
extension AwardsService {
    /// The wizard's inbox is picked (before sign-in, so it's celebrated here
    /// and synced silently later).
    func recordInboxChosen() {
        unlock("first-step")
    }

    func recordSignedUp() {
        unlock("committer")
    }

    /// Checked when the dashboard loads and when Getting Started closes.
    func recordProgress(_ progress: OutreachProgress) {
        if progress.steps.first(where: { $0.id == "profile" })?.done == true { unlock("introduction") }
        if progress.allDone { unlock("all-set") }
        guard let counts = progress.counts else { return }
        if counts.mailboxes >= 1 { unlock("listener") }
        if counts.campaigns >= 1 { unlock("campaigner") }
        if counts.emailsSent >= 1 { unlock("first-contact") }
        if counts.emailsSent >= 25 { unlock("follow-through") }
        if counts.emailsSent >= 200 { unlock("rainmaker") }
    }
}

/// `GET /getting-started/outreach`'s payload, read here only for the award
/// counts - the checklist page itself is TODDProfileKit's GettingStartedView.
struct OutreachProgress: Decodable {
    struct Step: Decodable {
        let id: String
        let done: Bool
    }

    struct Counts: Decodable {
        let mailboxes: Int
        let campaigns: Int
        let emailsSent: Int
    }

    let steps: [Step]
    let allDone: Bool
    let counts: Counts?
}

struct OutreachProgressEnvelope: Decodable {
    let data: OutreachProgress
}
