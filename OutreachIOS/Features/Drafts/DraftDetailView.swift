import SwiftUI

/// One of Maya's drafts: edit it and approve, send it back with a note for
/// Maya to rewrite, send yourself a test, or discard it.
struct DraftDetailView: View {
    let item: DraftItem
    @ObservedObject var store: DraftsStore
    @Binding var path: [OutreachRoute]
    @State private var subject: String
    @State private var message: String
    @State private var rewriteNote = ""
    @State private var working: Action?
    @State private var confirmDiscard = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private enum Action { case approve, rewrite, test, discard }

    init(item: DraftItem, store: DraftsStore, path: Binding<[OutreachRoute]>) {
        self.item = item
        self.store = store
        _path = path
        _subject = State(initialValue: item.subject)
        _message = State(initialValue: item.body)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("To", value: item.email.isEmpty ? item.contactName : "\(item.contactName) <\(item.email)>")
                if !item.companyName.isEmpty {
                    LabeledContent("Company", value: item.companyName)
                }
                TextField("Subject", text: $subject)
            }

            Section {
                TextEditor(text: $message).frame(minHeight: 240)
            } footer: {
                Text(item.isReply ? "A reply to their email. Approving sends it now." : "Approving moves it to the Outbox. Sending runs weekdays, 7am-11pm Pacific.")
            }

            if !item.rationale.isEmpty {
                Section("Why Maya wrote this") {
                    Text(item.rationale).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("What should Maya change? (optional)", text: $rewriteNote, axis: .vertical)
                    .lineLimit(2...4)
                Button {
                    Task { await run(.rewrite) }
                } label: {
                    label("Reject & Rewrite", systemImage: "arrow.triangle.2.circlepath", for: .rewrite)
                }
            } header: {
                Text("Not right?")
            } footer: {
                Text("Maya writes a new version right away.")
            }

            Section {
                Button {
                    Task { await run(.test) }
                } label: {
                    label("Send a Test to Me", systemImage: "envelope.badge", for: .test)
                }
                Button(role: .destructive) {
                    if confirmDiscard {
                        Task { await run(.discard) }
                    } else {
                        confirmDiscard = true
                    }
                } label: {
                    label(confirmDiscard ? "Tap Again to Discard" : "Discard Draft", systemImage: "trash", for: .discard)
                }
            }

            if let statusMessage {
                Section { Label(statusMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.footnote) }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .disabled(working != nil)
        .navigationTitle(item.contactName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(working == .approve ? "Approving…" : (item.isReply ? "Send" : "Approve")) {
                    Task { await run(.approve) }
                }
                .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func label(_ title: String, systemImage: String, for action: Action) -> some View {
        if working == action {
            HStack { ProgressView(); Text(action == .rewrite ? "Maya is rewriting…" : "Working…") }
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private func run(_ action: Action) async {
        working = action
        errorMessage = nil
        statusMessage = nil
        do {
            switch action {
            case .approve:
                try await store.approve(item, subject: subject, body: message)
                close()
            case .rewrite:
                try await store.reject(item, reason: rewriteNote)
                // Show Maya's new version if it's back already.
                if let rewritten = store.items.first(where: { $0.contactId == item.contactId }) {
                    subject = rewritten.subject
                    message = rewritten.body
                    rewriteNote = ""
                    statusMessage = "Here's Maya's new version."
                } else {
                    close()
                }
            case .test:
                try await store.sendTest(item)
                statusMessage = "Test sent to your email."
            case .discard:
                try await store.discard(item)
                close()
            }
        } catch {
            errorMessage = error.localizedDescription
            confirmDiscard = false
        }
        working = nil
    }

    private func close() {
        if path.last == .draftDetail(item) { path.removeLast() }
    }
}
