import SwiftUI

/// Drafts review, one at a time (design 4c): Find's pager across the top,
/// who it's to, the email as they'll read it (not raw HTML), why Maya wrote
/// it, and Send / Approve with Rewrite, Test to me and Discard below.
/// Opens on the draft that was tapped; Previous and Next move through the
/// rest without going back to the list.
struct DraftDetailView: View {
    @ObservedObject var store: DraftsStore
    @Binding var path: [OutreachRoute]
    @State private var currentId: String
    @State private var subject = ""
    @State private var message = ""
    /// The draft as Maya wrote it, sent as-is unless you edit it.
    @State private var originalBody = ""
    @State private var isEditing = false
    @State private var working: Action?
    @State private var isAskingRewrite = false
    @State private var rewriteNote = ""
    @State private var confirmDiscard = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @FocusState private var isTyping: Bool

    private enum Action { case approve, rewrite, test, discard }
    private let violet = Area.drafts.tint

    init(item: DraftItem, store: DraftsStore, path: Binding<[OutreachRoute]>) {
        self.store = store
        _path = path
        _currentId = State(initialValue: item.contactId)
    }

    private var items: [DraftItem] { store.items }
    private var index: Int? { items.firstIndex { $0.contactId == currentId } }
    private var item: DraftItem? { index.map { items[$0] } }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        recipient(item)
                        emailCard(item)
                        if !item.rationale.isEmpty {
                            TODDNote(label: "Why Maya wrote this", text: item.rationale)
                        }
                        if let statusMessage {
                            Label(statusMessage, systemImage: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Tint.green.foreground)
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.system(size: 13)).foregroundStyle(Ink.danger)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top) { pager }
                .safeAreaInset(edge: .bottom) { actionBar(item) }
                .disabled(working != nil)
            } else {
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.circle")
                } description: {
                    Text("No more drafts waiting.")
                }
            }
        }
        .background(Ink.bg)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: loadCurrent)
        .onChange(of: currentId) { _, _ in loadCurrent() }
        .alert("Rewrite this draft?", isPresented: $isAskingRewrite) {
            TextField("What should Maya change? (optional)", text: $rewriteNote)
            Button("Cancel", role: .cancel) {}
            Button("Rewrite") { Task { await run(.rewrite) } }
        } message: {
            Text("Maya writes a new version right away.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTyping = false }
            }
        }
    }

    // MARK: - Pager

    private var pager: some View {
        let previous = index.flatMap { $0 > 0 ? items[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < items.count ? items[$0 + 1] : nil }
        return HStack(spacing: 10) {
            circleButton("chevron.left", label: "Previous draft") { go(to: previous) }
                .disabled(previous == nil)
                .opacity(previous == nil ? 0.4 : 1)
            Spacer()
            VStack(spacing: 1) {
                Text("Drafts").font(.system(size: 15, weight: .bold))
                HStack(spacing: 4) {
                    Text("\((index ?? 0) + 1) of \(items.count)").font(.system(size: 12, weight: .semibold))
                    Text("·").foregroundStyle(Ink.muted)
                    Button("See list") { close() }
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.muted)
                }
            }
            Spacer()
            circleButton("chevron.right", label: "Next draft") { go(to: next) }
                .disabled(next == nil)
                .opacity(next == nil ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Ink.bg)
    }

    private func go(to draft: DraftItem?) {
        guard let draft else { return }
        statusMessage = nil
        currentId = draft.contactId
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: 44, height: 44)
                .background(Ink.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - The draft

    private func recipient(_ item: DraftItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            InitialsBadge(name: item.contactName, tint: violet, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.contactName).font(.system(size: 20, weight: .bold)).tracking(-0.3)
                Text([item.companyName, item.email].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            TagPill(text: item.isReply ? "Reply · sends now" : "Follow-up", tint: violet)
        }
    }

    private func emailCard(_ item: DraftItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                TextField("Subject", text: $subject, axis: .vertical)
                    .font(.system(size: 18, weight: .bold))
                Divider()
                TextField("Message", text: $message, axis: .vertical)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .lineLimit(8...60)
                    .focused($isTyping)
            } else {
                Text(subject).font(.system(size: 18, weight: .bold)).tracking(-0.2)
                Divider()
                Text(message)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(Ink.text)
                    .textSelection(.enabled)
            }
            Divider()
            HStack {
                Text(item.isReply ? "Sends from your inbox when you tap Send." : "Goes to the Outbox when you approve.")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
                Spacer()
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation { isEditing.toggle() }
                    if !isEditing { isTyping = false }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Ink.blueInk)
            }
        }
        .padding(16)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Actions

    private func actionBar(_ item: DraftItem) -> some View {
        StickyActionBar {
            Button {
                Task { await run(.approve) }
            } label: {
                Label(working == .approve ? "Sending…" : (item.isReply ? "Send reply" : "Approve"), systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillPrimary)
            .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            HStack(spacing: 8) {
                tile(working == .rewrite ? "Rewriting…" : "Rewrite", symbol: "arrow.triangle.2.circlepath") { isAskingRewrite = true }
                tile(working == .test ? "Sending…" : "Test to me", symbol: "envelope") { Task { await run(.test) } }
                tile(confirmDiscard ? "Tap again" : "Discard", symbol: "trash", isDestructive: true) {
                    if confirmDiscard { Task { await run(.discard) } } else { confirmDiscard = true }
                }
            }
        }
    }

    private func tile(_ title: String, symbol: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .bold))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(isDestructive ? Ink.danger : Ink.text)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func loadCurrent() {
        guard let item else { return }
        subject = item.subject
        originalBody = item.body
        message = CatalystText.plainText(fromHTML: item.body)
        isEditing = false
        confirmDiscard = false
        errorMessage = nil
    }

    /// Maya's HTML, unless you changed the words.
    private var bodyToSend: String {
        message == CatalystText.plainText(fromHTML: originalBody) ? originalBody : CatalystText.html(fromPlainText: message)
    }

    private func run(_ action: Action) async {
        guard let item, let index else { return }
        working = action
        errorMessage = nil
        statusMessage = nil
        // Where to go once this one is done: the next draft, else the one before.
        let following = index + 1 < items.count ? items[index + 1].contactId : (index > 0 ? items[index - 1].contactId : nil)
        do {
            switch action {
            case .approve:
                try await store.approve(item, subject: subject, body: bodyToSend)
                advance(to: following, note: item.isReply ? "Sent to \(item.contactName)." : "Approved. It's in the Outbox.")
            case .rewrite:
                try await store.reject(item, reason: rewriteNote)
                rewriteNote = ""
                if store.items.contains(where: { $0.contactId == item.contactId }) {
                    loadCurrent()
                    statusMessage = "Here's Maya's new version."
                } else {
                    advance(to: following, note: "Maya is rewriting it.")
                }
            case .test:
                try await store.sendTest(item)
                statusMessage = "Test sent to your email."
            case .discard:
                try await store.discard(item)
                advance(to: following, note: "Discarded.")
            }
        } catch {
            errorMessage = error.localizedDescription
            confirmDiscard = false
        }
        working = nil
    }

    private func advance(to nextId: String?, note: String) {
        guard let nextId else { close(); return }
        currentId = nextId
        statusMessage = note
    }

    private func close() {
        if case .draftDetail = path.last { path.removeLast() }
    }
}
