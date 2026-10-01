import SwiftUI

/// The reply page: Maya's draft (or a blank reply) to edit, "Help me write"
/// to have Maya draft one, and Send. Nothing goes out until Send is tapped.
struct NeedsYouReplyView: View {
    let item: NeedsYouItem
    @ObservedObject var store: NeedsYouStore
    @Binding var path: [OutreachRoute]
    @State private var subject: String
    @State private var message: String
    @State private var isDrafting = false
    @State private var isSending = false
    @State private var errorMessage: String?

    init(item: NeedsYouItem, useMayaDraft: Bool, store: NeedsYouStore, path: Binding<[OutreachRoute]>) {
        self.item = item
        self.store = store
        _path = path
        _subject = State(initialValue: useMayaDraft && item.hasMayaDraft ? item.mayaDraftSubject : item.replySubject)
        _message = State(initialValue: useMayaDraft && item.hasMayaDraft ? item.mayaDraftBody : "")
    }

    private var canSend: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSending && !isDrafting
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("To", value: item.email.isEmpty ? item.contactName : "\(item.contactName) <\(item.email)>")
                TextField("Subject", text: $subject)
            }

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 220)
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Write your reply…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } footer: {
                Text("Sent from your Outreach sender. Maya won't follow up with \(item.contactName) on her own.")
            }

            Section {
                Button {
                    Task { await helpMeWrite() }
                } label: {
                    if isDrafting {
                        HStack { ProgressView(); Text("Maya is writing…") }
                    } else {
                        Label(message.isEmpty ? "Help Me Write" : "Have Maya Rewrite It", systemImage: "sparkles")
                    }
                }
                .disabled(isDrafting || isSending)
            }

            if !item.replyText.isEmpty {
                Section("What \(item.contactName) said") {
                    Text(item.replyText).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Reply")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSending ? "Sending…" : "Send") {
                    Task { await send() }
                }
                .disabled(!canSend)
            }
        }
    }

    private func helpMeWrite() async {
        isDrafting = true
        errorMessage = nil
        do {
            let draft = try await store.draftReply(for: item)
            if !draft.subject.isEmpty { subject = draft.subject }
            if !draft.body.isEmpty { message = draft.body }
        } catch {
            errorMessage = error.localizedDescription
        }
        isDrafting = false
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await store.sendReply(to: item, subject: subject, body: message)
            // Back to the list - this person is no longer waiting on you.
            path.removeAll { route in
                route == .needsYouDetail(item) ||
                    route == .needsYouReply(item, useMayaDraft: true) ||
                    route == .needsYouReply(item, useMayaDraft: false)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
