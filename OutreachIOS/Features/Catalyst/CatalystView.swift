import SwiftUI

/// Catalyst, as on the web: Stale Contacts (how many to email, with the
/// stats), Send (the emailer, pausing on each of Maya's drafts) and History
/// (each batch's sends, opens and clicks). No pasted HTML templates on iOS -
/// every email is Maya's draft from the contact's relationship tip.
struct CatalystView: View {
    @ObservedObject var store: CatalystStore
    @State private var tab: CatalystTab = .stale

    var body: some View {
        VStack(spacing: 0) {
            Picker("Catalyst", selection: $tab) {
                ForEach(CatalystTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Group {
                if !store.hasLoaded {
                    ProgressView().frame(maxHeight: .infinity)
                } else {
                    switch tab {
                    case .stale: CatalystStaleTab(store: store) { tab = .send }
                    case .send: CatalystSendTab(store: store)
                    case .history: CatalystHistoryTab(store: store)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Catalyst")
        .navigationBarTitleDisplayMode(.inline)
        // Don't reload under a running batch - it would reshuffle the queue.
        .task { if !store.isRunning { await store.load() } }
    }
}

private enum CatalystTab: String, CaseIterable, Identifiable {
    case stale, send, history

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stale: return "Stale"
        case .send: return "Send"
        case .history: return "History"
        }
    }
    var symbol: String {
        switch self {
        case .stale: return "person.badge.clock"
        case .send: return "paperplane"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Stale Contacts

private struct CatalystStaleTab: View {
    @ObservedObject var store: CatalystStore
    let onContinue: () -> Void

    private static let presets = [25, 50, 100, 250, 500]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("STALE CONTACTS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text("People you may have forgotten").font(.title2.bold())
                    Text("The contacts who have gone the longest without a follow-up, so you can decide who deserves attention first.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if store.queue.isEmpty {
                    CatalystCard {
                        Text(store.errorMessage ?? "Nobody's waiting. Catalyst lists contacts with a first name, a company and an email address. Add some in Network and they'll show up here.")
                            .font(.subheadline)
                            .foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.red)
                    }
                } else {
                    batchPicker
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        CatalystStat(title: "Oldest gap", value: "\(store.oldestGap)", caption: "days since the stalest relationship was touched")
                        CatalystStat(title: "Average gap", value: "\(store.averageGap)", caption: "days since contact across this batch")
                        CatalystStat(title: "Queue ready", value: "\(store.batch.count)", caption: "contacts staged for Catalyst")
                        CatalystStat(title: "Urgent backlog", value: "\(store.urgentBacklog)", caption: "contacts at 30+ days since the last touch", isAlert: store.urgentBacklog > 0)
                    }
                    Button(action: onContinue) {
                        Text("Continue to Send")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OutreachTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .refreshable { if !store.isRunning { await store.load() } }
    }

    private var batchPicker: some View {
        CatalystCard {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: batchBinding, in: 1...store.batchLimit, step: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Batch size").font(.headline)
                        Text("\(min(store.batchSize, store.batchLimit))").font(.title3.monospacedDigit().bold())
                    }
                }
                .disabled(store.isRunning)
                HStack(spacing: 8) {
                    ForEach(Self.presets.filter { $0 <= store.batchLimit }, id: \.self) { size in
                        Button("\(size)") { store.batchSize = size }
                            .buttonStyle(.bordered)
                            .tint(store.batchSize == size ? OutreachTheme.accent : .secondary)
                            .disabled(store.isRunning)
                    }
                }
                Text("\(store.queue.count) contact\(store.queue.count == 1 ? "" : "s") waiting. Pick up to \(store.batchLimit).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var batchBinding: Binding<Int> {
        Binding(
            get: { min(store.batchSize, store.batchLimit) },
            set: { store.batchSize = $0 }
        )
    }
}

private struct CatalystStat: View {
    let title: String
    let value: String
    let caption: String
    var isAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.largeTitle.bold().monospacedDigit()).foregroundStyle(isAlert ? Color.orange : Color.primary)
            Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Send

private struct CatalystSendTab: View {
    @ObservedObject var store: CatalystStore
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let status = store.status { statusCard(status) }
                controls
                if let notice = store.notice {
                    Label(notice, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                activity
                CatalystCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SIGNAL ENGINE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Text("Catalyst sends the first email. After that, TODD owns the thread and adapts the follow-up from opens, clicks and silence.")
                            .font(.subheadline)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
    }

    private func statusCard(_ status: CatalystSendingStatus) -> some View {
        CatalystCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(status.isReady ? Color.green : Color.orange).frame(width: 10, height: 10)
                    Text(status.label).font(.headline)
                }
                Text(status.campaignHint).font(.subheadline).foregroundStyle(.secondary)
                Text("Today's cap: \(status.capForToday) · Used: \(status.usedToday) · Remaining: \(status.remainingToday)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        CatalystCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email Catalyst").font(.headline)
                        Text("Stalest contacts first.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(stateLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await store.start() }
                    } label: {
                        Label("Start", systemImage: "envelope").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OutreachTheme.accent)
                    .disabled(!store.canStart)

                    Button(role: .destructive) {
                        store.stop()
                    } label: {
                        Label("Stop", systemImage: "nosign").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.isRunning)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await store.reloadQueue() }
                    } label: {
                        Label("Reload Queue", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canReload)

                    Button {
                        Task { await store.loadSkipped() }
                    } label: {
                        Label("Load Skipped", systemImage: "list.bullet.indent").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canLoadSkipped)
                }
                .font(.subheadline)

                Toggle(isOn: Binding(get: { store.autoRun }, set: { store.setAutoRun($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto")
                        Text("Sends each email without stopping on the preview, while the app is open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(OutreachTheme.accent)

                HStack(spacing: 16) {
                    countLabel("Total", store.isRunning || store.totalCount > 0 ? store.totalCount : store.batch.count)
                    countLabel("Sent", store.sentCount)
                    countLabel("Remaining", store.remainingCount)
                    countLabel("Skipped", store.skipped.count)
                }
            }
        }
    }

    private func countLabel(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var stateLabel: String {
        switch store.phase {
        case .idle: return "Idle"
        case .drafting: return "Drafting"
        case .preview: return store.autoRun ? "Sending" : "Waiting on you"
        case .sending: return "Sending"
        case .finished: return "Done"
        }
    }

    @ViewBuilder
    private var activity: some View {
        switch store.phase {
        case .idle:
            CatalystCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready").font(.headline)
                    Text("Tap Start to have Maya draft the first email. The queue pauses on each preview so you can edit, send or skip it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .drafting(let contact):
            CatalystCard {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Maya is drafting for \(contact.fullName)...").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            }
        case .preview(let contact), .sending(let contact):
            preview(contact)
        case .finished:
            CatalystCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Batch finished").font(.headline)
                    Text("\(store.sentCount) sent\(store.skipped.isEmpty ? "" : ", \(store.skipped.count) skipped"). Signal Engine takes over the follow-ups. See History for opens and clicks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func preview(_ contact: CatalystContact) -> some View {
        let isSending = store.phase == .sending(contact)
        return CatalystCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.fullName).font(.title3.bold())
                    Text([contact.companyName, contact.email].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(contact.staleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(contact.daysSinceLastContact >= 30 ? .orange : OutreachTheme.accent)
                }

                field("Subject") {
                    TextField("Subject", text: $store.subject)
                }
                field("Message") {
                    TextField("Message", text: $store.message, axis: .vertical)
                        .lineLimit(8...30)
                        .focused($isEditing)
                }

                HStack {
                    Picker("Tone", selection: $store.tone) {
                        ForEach(CatalystTone.allCases) { tone in Text(tone.label).tag(tone) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button {
                        Task { await store.redraft() }
                    } label: {
                        Label("Redraft", systemImage: "sparkles")
                    }
                    .tint(OutreachTheme.accent)
                }
                .font(.subheadline)

                Button {
                    isEditing = false
                    Task { await store.sendCurrent() }
                } label: {
                    Text(isSending ? "Sending..." : "Send to \(contact.firstName)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OutreachTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .disabled(isSending)

                HStack {
                    Button("Skip") {
                        isEditing = false
                        Task { await store.skipCurrent() }
                    }
                    Spacer()
                    Button("Send test to me") {
                        Task { await store.sendTest() }
                    }
                }
                .font(.subheadline)
                .disabled(isSending)
            }
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.15)))
        }
    }
}

// MARK: - History

private struct CatalystHistoryTab: View {
    @ObservedObject var store: CatalystStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Catalyst runs with sent, open and click results.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if store.runs.isEmpty {
                    CatalystCard {
                        Text("No runs yet. Each batch you start shows up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(store.runs) { run in
                    CatalystRunCard(run: run)
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.refreshHistory() }
        .task { await store.refreshHistory() }
    }
}

private struct CatalystRunCard: View {
    let run: CatalystRun

    var body: some View {
        CatalystCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.name).font(.headline)
                    Text(run.status.capitalized).font(.caption).foregroundStyle(.secondary)
                    if let started = run.startedDate {
                        Text("Started \(started.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let finished = run.completedDate {
                        Text("Finished \(finished.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        tile("Sent", "\(run.sentCount)")
                        tile("Unique opens", "\(run.uniqueOpenedCount) · \(percent(run.openRate))")
                    }
                    GridRow {
                        tile("Unique clicks", "\(run.uniqueClickedCount) · \(percent(run.clickRate))")
                        tile("Queue", "\(run.queuedCount) queued")
                    }
                }
            }
        }
    }

    private func percent(_ rate: Double) -> String {
        "\(Int((rate * 100).rounded()))%"
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12)))
    }
}

// MARK: - Shared

private struct CatalystCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
