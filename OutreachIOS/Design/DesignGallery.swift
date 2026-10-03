#if DEBUG
import SwiftUI

/// Debug builds only: renders a redesigned screen with sample data, without
/// signing in, so it can be checked in the simulator. Launch with
/// `-designGallery home` (or another `Screen`), as PaywallScreenshot does.
enum DesignGallery {
    enum Screen: String {
        case home, components, catalystStale, catalystSend, catalystPreview, catalystHistory, draftsList, draftReview, inbox, message, activity, needsYou, needsYouDetail
    }

    static var current: Screen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-designGallery"), arguments.indices.contains(index + 1) else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }

    @MainActor @ViewBuilder
    static func view(for screen: Screen) -> some View {
        switch screen {
        case .home: HomeSample()
        case .components: ComponentsSample()
        case .catalystStale: CatalystSample(tab: .stale)
        case .catalystSend: CatalystSample(tab: .send)
        case .catalystPreview: CatalystSample(tab: .send, previewing: true)
        case .catalystHistory: CatalystSample(tab: .history)
        case .draftsList: DraftsSample(review: false)
        case .draftReview: DraftsSample(review: true)
        case .inbox: InboxSample()
        case .activity: NavigationStack { ActivityView(apiClient: sampleAPIClient(), onOpen: { _ in }, sample: ActivitySample.items) }
        case .needsYou: NeedsYouSample(detail: false)
        case .needsYouDetail: NeedsYouSample(detail: true)
        case .message: NavigationStack { MessageDetailView(apiClient: sampleAPIClient(), mailboxId: "m", messageId: "1", sample: InboxSample.messages[0]) }
        }
    }

    static func decode<T: Decodable>(_ json: String) -> T {
        // swiftlint:disable:next force_try
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

private struct HomeSample: View {
    var body: some View {
        NavigationStack {
            HomeDashboard(
                model: HomeModel(
                    userName: "Ty Showers",
                    brokenMailbox: "ty.showers@taliferro.tech",
                    needsYouNames: ["Theodore Ricks-Freeman", "George Dimov", "William Pierce", "Glenn Torrez", "Robert Leung"],
                    draftsCount: 191,
                    draftsDetail: "waiting for approval",
                    inboxNewCount: 7,
                    catalystCount: 500,
                    activityDetail: "Maya's done for today",
                    summary: DesignGallery.decode(#"{"activeThreads":358,"draftReady":191,"stalledWaiting":304,"hotLeads":0,"warmLeads":0,"queuedActions":0,"sending":0,"needsHuman":5}"#)
                ),
                actions: HomeActions(reconnect: {}, needsYou: {}, startNeedsYou: {}, drafts: {}, inbox: {}, catalyst: {}, activity: {})
            ) {
                Button("Profile") {}
            } footer: {
                EmptyView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

@MainActor
private func sampleAPIClient() -> OutreachAPIClient {
    OutreachAPIClient(config: AppConfig.fromBundle(), authService: AuthService())
}

private struct CatalystSample: View {
    @StateObject private var store: CatalystStore
    let tab: CatalystTab

    init(tab: CatalystTab, previewing: Bool = false) {
        self.tab = tab
        let store = CatalystStore(apiClient: sampleAPIClient())
        let people = [("Bob", "Polmatier", "Polmatier Consulting", 9), ("Bruce", "Cheatham III", "Cheatham & Co.", 9), ("Charlotte", "Marshall", "TKG & Associates LLC", 9), ("Doug", "Bryan", "Idaho Tower Construction", 8), ("Elizabeth", "Miller", "Minto Island Growers", 8), ("Jamie", "Halimi", "Desco Tools Co", 34)]
        let queue: [CatalystContact] = (0..<500).map { index in
            let person = people[index % people.count]
            return DesignGallery.decode(#"{"id":"c\#(index)","firstName":"\#(person.0)","lastName":"\#(person.1)","companyName":"\#(person.2)","email":"\#(person.0.lowercased())@example.com","daysSinceLastContact":\#(person.3)}"#)
        }
        let status: CatalystSendingStatus = DesignGallery.decode(#"{"level":"ready","label":"Ready to send","detail":"","campaignHint":"","capForToday":100,"usedToday":0,"remainingToday":100}"#)
        let runs: [CatalystRun] = DesignGallery.decode(#"""
        [{"id":"r1","name":"Stale Contacts 2026-09-28","status":"completed","queuedCount":1000,"skippedCount":0,"sentCount":985,"uniqueOpenedCount":484,"uniqueClickedCount":234,"openRate":0.49,"clickRate":0.24,"startedAt":"2026-09-28T20:01:09Z","completedAt":"2026-09-28T20:08:27Z"},
         {"id":"r2","name":"Stale Contacts 2026-09-28","status":"completed","queuedCount":25,"skippedCount":0,"sentCount":25,"uniqueOpenedCount":14,"uniqueClickedCount":4,"openRate":0.56,"clickRate":0.16,"startedAt":"2026-09-28T19:59:48Z","completedAt":"2026-09-28T20:00:10Z"},
         {"id":"r3","name":"Stale Contacts 2026-09-28","status":"active","queuedCount":25,"skippedCount":0,"sentCount":0,"uniqueOpenedCount":0,"uniqueClickedCount":0,"openRate":0,"clickRate":0,"startedAt":"2026-09-28T19:55:52Z","completedAt":""},
         {"id":"r4","name":"Stale Contacts 2026-09-25","status":"completed","queuedCount":320,"skippedCount":8,"sentCount":312,"uniqueOpenedCount":128,"uniqueClickedCount":37,"openRate":0.41,"clickRate":0.12,"startedAt":"2026-09-25T21:22:00Z","completedAt":"2026-09-25T21:31:00Z"}]
        """#)
        store.loadSample(queue: queue, status: status, runs: runs, previewing: previewing)
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack {
            CatalystView(store: store, tab: tab)
        }
    }
}

private struct DraftsSample: View {
    @StateObject private var store: DraftsStore
    @State private var path: [OutreachRoute] = []
    let review: Bool

    init(review: Bool) {
        self.review = review
        let store = DraftsStore(apiClient: sampleAPIClient())
        let items: [DraftItem] = DesignGallery.decode(#"""
        [{"contactId":"a","contactName":"Charlotte Marshall","companyName":"TKG & Associates LLC","email":"cmarshall@tkg.com","kind":"outbound","subject":"How do you manage project momentum?","body":"<p>It's interesting how many projects stall because the right follow-up isn't in place.</p>","rationale":"","stage":"","updatedAt":"2026-10-02T13:00:00Z"},
         {"contactId":"b","contactName":"Utilio Candelara","companyName":"Labor Local 332","email":"utiliocandelaria@gmail.com","kind":"reply","subject":"How construction workers stay engaged","body":"<p>When construction workers feel disconnected, it can lead to delays and inefficiencies on projects. This is especially crucial in a labor union environment where advocacy and service are key to maintaining morale and productivity.</p><p>It might be worth exploring how effective communication and engagement strategies can enhance worker involvement and project outcomes. Would you be open to a brief conversation?</p><p>Ty Showers<br>Taliferro Tech</p>","rationale":"Addresses worker engagement in construction and suggests a conversation about communication strategies for the union.","stage":"","updatedAt":"2026-10-02T13:00:00Z"},
         {"contactId":"c","contactName":"David Fouche","companyName":"J2 Solutions","email":"dfouche@j2.com","kind":"outbound","subject":"The challenge of project momentum","body":"<p>Project management often reveals a hidden struggle: while teams plan and execute tasks, momentum slips.</p>","rationale":"","stage":"","updatedAt":"2026-10-02T12:00:00Z"},
         {"contactId":"d","contactName":"Elizabeth Miller","companyName":"Minto Island Growers","email":"emiller@minto.com","kind":"outbound","subject":"Finding clarity in outreach","body":"<p>It's interesting how many outreach efforts stall due to unclear next steps.</p>","rationale":"","stage":"","updatedAt":"2026-10-02T12:00:00Z"}]
        """#)
        store.loadSample(items)
        _store = StateObject(wrappedValue: store)
        if review { _path = State(initialValue: [.drafts, .draftDetail(items[1])]) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            DraftsView(store: store, path: $path)
                .navigationDestination(for: OutreachRoute.self) { route in
                    switch route {
                    case .draftDetail(let item): DraftDetailView(item: item, store: store, path: $path)
                    default: DraftsView(store: store, path: $path)
                    }
                }
        }
    }
}

private struct InboxSample: View {
    @StateObject private var store = InboxStore(apiClient: sampleAPIClient())
    @State private var path: [OutreachRoute] = []

    static let messages: [MailboxMessage] = DesignGallery.decode(#"""
    [{"id":"1","mailboxId":"m","subject":"Automatic reply: Which do you think is better Finding or Searching?","fromName":"Robert Leung","fromEmail":"rleung@rosendin.com","receivedAt":"2026-10-02T09:31:00Z","unread":true,"preview":"I am currently out of the office and will return on Monday, October 5, 2026. If any immediate needs, please contact Matt Zika at mzika@rosendin.com.","text":"I am currently out of the office and will return on Monday, October 5, 2026. If any immediate needs, please contact Matt Zika at mzika@rosendin.com.","signalSummary":"Robert Leung is out of the office until October 5, 2026, and has provided an alternate contact for immediate needs.","recommendedAction":"Pause until Oct 5"},
     {"id":"2","mailboxId":"m","subject":"Get ready for your LinkedIn Ads Consultation","fromName":"LinkedIn","fromEmail":"news@linkedin.com","receivedAt":"2026-10-01T15:00:00Z","unread":true,"preview":"Marketing email","signalSummary":"Marketing email"},
     {"id":"3","mailboxId":"m","subject":"Fw: Meeting assets for The DC Voice's Zoom Meeting are ready!","fromName":"Theodore Freeman","fromEmail":"tgfreeman@thedcvoice.com","receivedAt":"2026-10-01T16:22:00Z","unread":true,"preview":"________________________________ From: Zoom <no-reply@zoom.us> Sent: Thursday","signalSummary":"Forwarded Zoom recording and transcript"},
     {"id":"4","mailboxId":"m","subject":"Delivery Status Notification (Failure)","fromName":"Mail Delivery Subsystem","fromEmail":"mailer-daemon@googlemail.com","receivedAt":"2026-09-29T15:00:00Z","unread":false,"preview":"Address not found","signalSummary":"jake@ may not exist"},
     {"id":"5","mailboxId":"m","subject":"Re: Which do you think is better, Finding or Searching?","fromName":"Dana Lee","fromEmail":"dana@leeco.com","receivedAt":"2026-09-28T15:00:00Z","unread":true,"preview":"Thursday works for me.","signalSummary":"Wants to meet Thursday"},
     {"id":"6","mailboxId":"m","subject":"Automatic reply: We have been brainwashed into searching","fromName":"William Pierce","fromEmail":"wpierce@atchadwick.com","receivedAt":"2026-09-28T14:00:00Z","unread":true,"preview":"I will be out of the office Sept 28, 29, and 30th, with limited availability to email.","signalSummary":"Out Sept 28–30, back Oct 1"},
     {"id":"7","mailboxId":"m","subject":"Automatic reply: We have been brainwashed into searching","fromName":"Glenn Torrez","fromEmail":"gtorrez@example.com","receivedAt":"2026-09-28T13:00:00Z","unread":true,"preview":"This email address is no longer active. Please call the office at 760.929.9700.","signalSummary":"Address no longer active, office 760.929.9700"}]
    """#)

    var body: some View {
        NavigationStack(path: $path) {
            InboxView(store: store, defaultEmail: "", path: $path)
        }
        .onAppear {
            let mailbox: MailboxSummary = DesignGallery.decode(#"{"id":"m","emailAddress":"ty.showers@taliferro.tech","providerLabel":"Other IMAP","isPrimary":true,"lastSyncAt":"\#(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-480)))"}"#)
            store.loadSample(mailbox: mailbox, messages: Self.messages)
        }
    }
}

private enum ActivitySample {
    static var items: [ActivityItem] {
        let now = Date()
        func iso(_ hoursAgo: Double) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-hoursAgo * 3600)) }
        return DesignGallery.decode(#"""
        [{"id":"1","category":"maya","title":"Maya's done for today","body":"256 sent, 2 replies, 191 drafts waiting, 5 need you. See the summary.","createdAt":"\#(iso(0.5))"},
         {"id":"2","category":"mailbox","title":"Can't reach ty.showers@taliferro.tech","body":"Reconnect so Maya can keep sending.","createdAt":"\#(iso(1))"},
         {"id":"3","category":"replies","title":"Robert Leung is out of office","body":"I am currently out of the office and will return on Monday, October 5.","createdAt":"\#(iso(2))"},
         {"id":"4","category":"replies","title":"Robert Leung is out of office","body":"I am currently out of the office and will return on Monday, October 5.","createdAt":"\#(iso(2))"},
         {"id":"5","category":"maya","title":"Maya couldn't start today","body":"She's at her limit of open tasks. Close out a few Moves and she'll plan again tomorrow.","createdAt":"\#(iso(26))"},
         {"id":"6","category":"replies","title":"Theodore Ricks-Freeman replied","body":"________________________________ From: Zoom <no-reply@zoom.us> Sent: Thursday","createdAt":"\#(iso(27))"},
         {"id":"7","category":"replies","title":"Theodore Ricks-Freeman replied","body":"________________________________ From: Zoom <no-reply@zoom.us> Sent: Thursday","createdAt":"\#(iso(27))"},
         {"id":"8","category":"catalyst","title":"Catalyst batch finished","body":"42 sent, 3 failed","createdAt":"\#(iso(50))"}]
        """#)
    }
}

private struct NeedsYouSample: View {
    @StateObject private var store = NeedsYouStore(apiClient: sampleAPIClient())
    @State private var path: [OutreachRoute] = []
    let detail: Bool

    static let items: [NeedsYouItem] = DesignGallery.decode(#"""
    [{"contactId":"t","contactName":"Theodore Ricks-Freeman","companyName":"The DC Voice","email":"tg@thedcvoice.com","phone":"2025550100","lastSubject":"We have been brainwashed into searching, why not Find?","replyText":"________________________________\nFrom: Zoom <no-reply@zoom.us>\nSent: Thursday, October 1, 2026 4:22 PM\n\nMeeting assets for Theodore Freeman - The DC Voice's Zoom Meeting are ready!","replyClean":"Meeting assets for Theodore Freeman - The DC Voice's Zoom Meeting are ready!\n\nReview action items\n\nRecording\nDuration: 00:48:52","replyKind":"automated","replySummary":"The email is an automated notification from Zoom about meeting assets being ready, not a direct reply from Theodore Ricks-Freeman.","repliedAt":"2026-10-01T16:22:00Z","reasonKey":"no_safe_draft","reasonLabel":"No safe draft","reasonDetail":"","nextMove":"","mayaDraftSubject":"","mayaDraftBody":""},
     {"contactId":"g","contactName":"George Dimov","companyName":"Dimov Tax","email":"g@dimov.com","phone":"","lastSubject":"Quick question","replyText":"Happy to talk. Could we schedule a call about tax planning next week?","replyClean":"Happy to talk. Could we schedule a call about tax planning next week?","replyKind":"interested","replySummary":"Offered to schedule a call about tax planning.","repliedAt":"2026-09-24T16:22:00Z","reasonKey":"reply_came_in","reasonLabel":"Reply came in","reasonDetail":"","nextMove":"","mayaDraftSubject":"Re: Quick question","mayaDraftBody":"Great - how's Tuesday at 10?"},
     {"contactId":"w","contactName":"William Pierce","companyName":"A.T. Chadwick","email":"w@atc.com","phone":"","lastSubject":"Finding","replyText":"I will be out of the office Sept 28, 29, and 30th, with limited availability to email.","replyClean":"I will be out of the office Sept 28, 29, and 30th, with limited availability to email.","replyKind":"out_of_office","replySummary":"","repliedAt":"2026-09-28T16:22:00Z","reasonKey":"no_safe_draft","reasonLabel":"No safe draft","reasonDetail":"","nextMove":"","mayaDraftSubject":"","mayaDraftBody":""}]
    """#)

    var body: some View {
        NavigationStack(path: $path) {
            NeedsYouView(store: store, path: $path)
                .navigationDestination(for: OutreachRoute.self) { route in
                    if case .needsYouDetail(let item) = route {
                        NeedsYouDetailView(item: item, store: store, path: $path)
                    }
                }
        }
        .onAppear {
            store.loadSample(Self.items)
            if detail { path = [.needsYouDetail(Self.items[0])] }
        }
    }
}

private struct ComponentsSample: View {
    @State private var segment = 0
    @State private var chip = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PillSegments(selection: $segment, options: [(0, "Stale"), (1, "Send"), (2, "History")])
                FilterChips(selection: $chip, options: [(0, "All"), (1, "Replies"), (2, "Auto-replies"), (3, "Bounces")])
                HStack {
                    TagPill(text: "Reply", tint: .green)
                    TagPill(text: "Out of office", tint: .yellow)
                    TagPill(text: "Bounce", tint: .pink)
                    TagPill(text: "Forward", tint: .blue)
                    TagPill(text: "Newsletter")
                }
                TODDNote(label: "What TODD sees", text: "Robert Leung is out of the office until October 5, 2026, and has provided an alternate contact for immediate needs.")
                Button("Send reply") {}.buttonStyle(.pillPrimary).frame(maxWidth: .infinity)
                HStack {
                    Button("Reload queue") {}.buttonStyle(.pill(.secondary, height: 44))
                    Button("Reconnect") {}.buttonStyle(.pillDark)
                    Button("Discard") {}.buttonStyle(.pill(.danger, height: 44))
                }
                HStack {
                    InitialsBadge(name: "Utilio Candelara", tint: .violet, size: 48)
                    InitialsBadge(name: "Bob Polmatier", tint: .cyan)
                    InitialsBadge(name: "Robert Leung", tint: .blue)
                }
            }
            .padding(16)
        }
        .background(Ink.bg)
    }
}
#endif
