import SwiftUI

/// Catalyst (design 4i-4k): Stale (who to email, with the stats and who's up
/// next), Send (progress, Auto-send, and each of Maya's drafts to send or
/// skip) and History (each run's sends, opens and clicks). No pasted HTML
/// templates on iOS - every email is Maya's draft from the contact's
/// relationship tip. Cyan throughout, the main action blue.
struct CatalystView: View {
    @ObservedObject var store: CatalystStore
    @State private var tab: CatalystTab

    init(store: CatalystStore, tab: CatalystTab = .stale) {
        self.store = store
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            PillSegments(selection: $tab, options: CatalystTab.allCases.map { ($0, $0.title) })
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

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
        .background(Ink.bg)
        .navigationTitle("Catalyst")
        .navigationBarTitleDisplayMode(.inline)
        // Don't reload under a running batch - it would reshuffle the queue.
        .task { if !store.isRunning { await store.load() } }
    }
}

enum CatalystTab: CaseIterable, Hashable {
    case stale, send, history

    var title: String {
        switch self {
        case .stale: return "Stale"
        case .send: return "Send"
        case .history: return "History"
        }
    }
}

private let cyan = Area.catalyst.tint

// MARK: - Stale (4i)

private struct CatalystStaleTab: View {
    @ObservedObject var store: CatalystStore
    let onContinue: () -> Void

    private static let presets = [25, 50, 100, 250, 500]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.queue.isEmpty {
                    SurfaceCard {
                        Text(store.errorMessage ?? "Nobody's waiting. Catalyst lists contacts with a first name, a company and an email address. Add some in Network and they'll show up here.")
                            .font(.system(size: 15))
                            .foregroundStyle(store.errorMessage == nil ? Ink.muted : Ink.danger)
                    }
                } else {
                    chooser
                    upNext
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .refreshable { if !store.isRunning { await store.load() } }
        .safeAreaInset(edge: .bottom) {
            if !store.queue.isEmpty {
                StickyActionBar {
                    Button(action: onContinue) {
                        Text("Continue with \(store.batch.count) →").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pillPrimary)
                }
            }
        }
    }

    private var chooser: some View {
        TintCard(tint: cyan) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("People you may have forgotten")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.3)
                    Text("\(store.queue.count) contact\(store.queue.count == 1 ? "" : "s") waiting. Pick up to \(store.batchLimit).")
                        .font(.system(size: 14))
                }
                .foregroundStyle(cyan.foreground)

                FlowChips(sizes: sizes, selected: min(store.batchSize, store.batchLimit), isDisabled: store.isRunning) { store.batchSize = $0 }

                HStack(spacing: 10) {
                    statTile("\(store.oldestGap) day\(store.oldestGap == 1 ? "" : "s")", "Oldest gap")
                    statTile("\(store.urgentBacklog)", "30+ days untouched")
                }
            }
        }
    }

    /// The presets that fit, plus "everyone" when fewer than 500 are waiting.
    private var sizes: [Int] {
        var sizes = Self.presets.filter { $0 < store.batchLimit }
        sizes.append(store.batchLimit)
        return sizes
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(Ink.text)
            Text(label).font(.system(size: 12)).foregroundStyle(Ink.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Up next").font(.system(size: 15, weight: .bold))
                Spacer()
                Text("\(store.batch.count) staged").font(.system(size: 13)).foregroundStyle(Ink.muted)
            }
            .padding(.horizontal, 4)
            ForEach(store.batch.prefix(50)) { contact in
                HStack(spacing: 12) {
                    InitialsBadge(name: contact.fullName, tint: cyan, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(contact.fullName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let company = contact.companyName, !company.isEmpty {
                            Text(company).font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(contact.daysSinceLastContact)d")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(contact.daysSinceLastContact >= 30 ? Ink.danger : Ink.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if store.batch.count > 50 {
                Text("and \(store.batch.count - 50) more")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }
}

/// Batch-size chips that wrap: the selected one solid cyan with dark text.
private struct FlowChips: View {
    let sizes: [Int]
    let selected: Int
    let isDisabled: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { ForEach(sizes.prefix(3), id: \.self, content: chip) }
                HStack(spacing: 8) { ForEach(sizes.dropFirst(3), id: \.self, content: chip) }
            }
        }
    }

    private var chips: some View {
        ForEach(sizes, id: \.self, content: chip)
    }

    private func chip(_ size: Int) -> some View {
        let isSelected = size == selected
        return Button("\(size)") { onSelect(size) }
            .font(.system(size: 15, weight: .bold))
            .frame(minWidth: 48)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .foregroundStyle(isSelected ? Color(hex: 0x0f1115) : Ink.text)
            .background(isSelected ? cyan.solid : Ink.bg, in: Capsule())
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Send (4j)

private struct CatalystSendTab: View {
    @ObservedObject var store: CatalystStore
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = store.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(Ink.danger)
                }
                switch store.phase {
                case .preview(let contact), .sending(let contact):
                    progressStrip
                    preview(contact)
                default:
                    progressCard
                    autoSendRow
                    if let notice = store.notice {
                        Text(notice).font(.system(size: 13)).foregroundStyle(Ink.muted).padding(.horizontal, 4)
                    }
                    TODDNote(label: "Signal Engine", text: "Catalyst sends the first email. After that, TODD owns the thread and adapts the follow-up from opens, clicks and silence.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
    }

    private var total: Int { store.isRunning || store.totalCount > 0 ? store.totalCount : store.batch.count }

    // The ring, with what's left.
    private var progressCard: some View {
        SurfaceCard(radius: 24, padding: 20) {
            VStack(spacing: 18) {
                statusTag
                ZStack {
                    Circle().stroke(Ink.surface2, lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(store.sentCount) / CGFloat(total) : 0)
                        .stroke(cyan.solid, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: store.sentCount)
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(store.sentCount)").font(.system(size: 52, weight: .bold)).tracking(-2)
                            Text("/\(total)").font(.system(size: 20, weight: .semibold)).foregroundStyle(Ink.muted)
                        }
                        Text(phaseLine).font(.system(size: 13)).foregroundStyle(Ink.muted)
                    }
                    .monospacedDigit()
                }
                .frame(width: 180, height: 180)
                HStack {
                    figure("\(store.remainingCount > 0 ? store.remainingCount : (store.isRunning ? 0 : total - store.sentCount))", "Remaining")
                    figure("\(store.skipped.count)", "Skipped")
                    figure(store.status.map { "\($0.remainingToday)" } ?? "–", "Left today")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The compact version above an email waiting on you.
    private var progressStrip: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Ink.surface2, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(store.sentCount) / CGFloat(total) : 0)
                    .stroke(cyan.solid, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(store.sentCount) of \(total) sent").font(.system(size: 15, weight: .bold))
                Text("\(store.remainingCount) left · \(store.skipped.count) skipped").font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
            Spacer()
            if store.autoRun { TagPill(text: "Auto-send", tint: cyan) }
        }
        .padding(12)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var phaseLine: String {
        switch store.phase {
        case .drafting(let contact): return "drafting \(contact.firstName)…"
        case .finished: return "sent · done"
        default: return "sent"
        }
    }

    @ViewBuilder
    private var statusTag: some View {
        if case .drafting = store.phase {
            TagPill(text: "Maya is drafting", tint: .green, symbol: "sparkle")
        } else if let status = store.status {
            TagPill(text: "● \(status.label)", tint: status.isReady ? .green : .yellow)
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(Ink.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var autoSendRow: some View {
        Toggle(isOn: Binding(get: { store.autoRun }, set: { store.setAutoRun($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-send").font(.system(size: 15, weight: .bold))
                Text("Send each email without stopping on the preview, while the app is open.")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
            }
        }
        .tint(cyan.solid)
        .padding(16)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // One of Maya's emails, waiting on you - laid out like a draft (4c).
    private func preview(_ contact: CatalystContact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                InitialsBadge(name: contact.fullName, tint: cyan, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.fullName).font(.system(size: 17, weight: .bold))
                    Text([contact.companyName, contact.email].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                }
                Spacer()
                TagPill(text: "\(contact.daysSinceLastContact)d quiet", tint: cyan)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Subject", text: $store.subject, axis: .vertical)
                    .font(.system(size: 17, weight: .bold))
                Divider()
                TextField("Message", text: $store.message, axis: .vertical)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .lineLimit(6...40)
                    .focused($isEditing)
                Divider()
                HStack {
                    Menu {
                        Picker("Tone", selection: $store.tone) {
                            ForEach(CatalystTone.allCases) { tone in Text(tone.label).tag(tone) }
                        }
                    } label: {
                        Label(store.tone.label, systemImage: "slider.horizontal.3")
                    }
                    Spacer()
                    Button {
                        Task { await store.redraft() }
                    } label: {
                        Label("Redraft", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .tint(Ink.blueInk)
            }
            .padding(16)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let notice = store.notice {
                Text(notice).font(.system(size: 13)).foregroundStyle(Ink.muted)
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        switch store.phase {
        case .preview(let contact), .sending(let contact):
            let isSending = store.phase == .sending(contact)
            StickyActionBar {
                Button {
                    isEditing = false
                    Task { await store.sendCurrent() }
                } label: {
                    Label(isSending ? "Sending…" : "Send to \(contact.firstName)", systemImage: "paperplane").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pillPrimary)
                .disabled(isSending)
                HStack(spacing: 8) {
                    actionTile("Skip", symbol: "forward") { Task { await store.skipCurrent() } }
                    actionTile("Test to me", symbol: "envelope") { Task { await store.sendTest() } }
                    actionTile("Stop", symbol: "stop.circle", role: .destructive) { store.stop() }
                }
                .disabled(isSending)
            }
        case .drafting:
            StickyActionBar {
                Button(role: .destructive) { store.stop() } label: {
                    Label("Stop", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.danger))
            }
        case .idle, .finished:
            StickyActionBar {
                Button {
                    Task { await store.start() }
                } label: {
                    Label(store.phase == .finished ? "Start another batch" : "Start · Maya drafts the first", systemImage: "paperplane").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pillPrimary)
                .disabled(!store.canStart)
                HStack(spacing: 8) {
                    Button {
                        Task { await store.reloadQueue() }
                    } label: {
                        Label("Reload queue", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .disabled(!store.canReload)
                    Button {
                        Task { await store.loadSkipped() }
                    } label: {
                        Text("Load skipped").frame(maxWidth: .infinity)
                    }
                    .disabled(!store.canLoadSkipped)
                }
                .buttonStyle(.pill(.secondary, height: 44))
            }
        }
    }

    private func actionTile(_ title: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(role == .destructive ? Ink.danger : Ink.text)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History (4k)

private struct CatalystHistoryTab: View {
    @ObservedObject var store: CatalystStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    legend("Opens", Ink.blue)
                    legend("Clicks", Ink.violet)
                }
                .padding(.horizontal, 4)
                if store.runs.isEmpty {
                    SurfaceCard {
                        Text("No runs yet. Each batch you start shows up here.")
                            .font(.system(size: 15))
                            .foregroundStyle(Ink.muted)
                    }
                }
                ForEach(store.runs) { run in
                    CatalystRunCard(run: run)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.refreshHistory() }
        .task { await store.refreshHistory() }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13)).foregroundStyle(Ink.muted)
        }
    }
}

private struct CatalystRunCard: View {
    let run: CatalystRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(run.sentCount)").font(.system(size: 22, weight: .bold)).monospacedDigit()
                    Text("sent").font(.system(size: 11)).foregroundStyle(Ink.muted)
                }
            }
            bar(run.openRate, Ink.blue)
            bar(run.clickRate, Ink.violet)
        }
        .padding(16)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "Stale Contacts · Sep 28" from "Stale Contacts 2026-09-28".
    private var title: String {
        let base = run.name.replacingOccurrences(of: #"\s*\d{4}-\d{2}-\d{2}$"#, with: "", options: .regularExpression)
        guard let started = run.startedDate else { return run.name }
        return "\(base) · \(started.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var subtitle: String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        guard let started = run.startedDate else { return run.status.capitalized }
        if run.status == "active" { return "Active · started \(started.formatted(time))" }
        if let finished = run.completedDate { return "\(run.status.capitalized) · \(started.formatted(time))–\(finished.formatted(time))" }
        return run.status.capitalized
    }

    private func bar(_ rate: Double, _ color: Color) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.surface2)
                    Capsule().fill(color).frame(width: geometry.size.width * min(max(rate, 0), 1))
                }
            }
            .frame(height: 6)
            Text("\(Int((rate * 100).rounded()))%")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}
