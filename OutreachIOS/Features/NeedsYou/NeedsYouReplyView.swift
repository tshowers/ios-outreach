import SwiftUI

/// The reply: Maya's draft (or a blank one, or one she writes now for "Help
/// me write it") to edit, then Send. Nothing goes out until Send is tapped.
/// Sent, it goes back to the person view, where the next one takes over.
struct NeedsYouReplyView: View {
    let item: NeedsYouItem
    @ObservedObject var store: NeedsYouStore
    @Binding var path: [OutreachRoute]
    /// "Help me write it": Maya drafts as soon as this opens.
    var autoDraft = false
    @State private var subject: String
    @State private var message: String
    @State private var isDrafting = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isTyping: Bool

    init(item: NeedsYouItem, useMayaDraft: Bool, store: NeedsYouStore, path: Binding<[OutreachRoute]>, autoDraft: Bool = false) {
        self.item = item
        self.store = store
        self.autoDraft = autoDraft
        _path = path
        _subject = State(initialValue: useMayaDraft && item.hasMayaDraft ? item.mayaDraftSubject : item.replySubject)
        _message = State(initialValue: useMayaDraft && item.hasMayaDraft ? CatalystText.plainText(fromHTML: item.mayaDraftBody) : "")
    }

    private var canSend: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSending && !isDrafting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    InitialsBadge(name: item.contactName, tint: Area.needsYou.tint, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("To \(item.contactName)").font(.system(size: 17, weight: .bold))
                        Text(item.email).font(.system(size: 13)).foregroundStyle(Ink.muted)
                    }
                }

                if !item.readableReply.isEmpty {
                    Text(item.readableReply)
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(4)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Subject", text: $subject)
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.muted)
                    Divider()
                    if isDrafting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Maya is writing…").foregroundStyle(Ink.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        TextField("Write your reply…", text: $message, axis: .vertical)
                            .font(.system(size: 16))
                            .lineSpacing(3)
                            .lineLimit(8...40)
                            .focused($isTyping)
                    }
                }
                .padding(16)
                .background(Ink.bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Ink.blue, lineWidth: 2))

                Button {
                    Task { await helpMeWrite() }
                } label: {
                    Label(message.isEmpty ? "Help me write it" : "Have Maya rewrite it", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Tint.green.foreground)
                .disabled(isDrafting || isSending)

                Text("Sent from your Outreach sender. Maya won't follow up with \(item.firstName) on her own.")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)

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
        .background(Ink.bg)
        .safeAreaInset(edge: .bottom) {
            StickyActionBar {
                Button {
                    Task { await send() }
                } label: {
                    Label(isSending ? "Sending…" : "Send", systemImage: "paperplane").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pillPrimary)
                .disabled(!canSend)
            }
        }
        .navigationTitle("Reply")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTyping = false }
            }
        }
        .task { if autoDraft && message.isEmpty { await helpMeWrite() } }
    }

    private func helpMeWrite() async {
        isDrafting = true
        errorMessage = nil
        do {
            let draft = try await store.draftReply(for: item)
            if !draft.subject.isEmpty { subject = draft.subject }
            if !draft.body.isEmpty { message = CatalystText.plainText(fromHTML: draft.body) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isDrafting = false
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await store.sendReply(to: item, subject: subject, body: CatalystText.html(fromPlainText: message))
            store.showToast("Sent to \(item.firstName)", canUndo: false)
            // Back to the person view, which moves on to whoever's next.
            if case .needsYouReply = path.last { path.removeLast() } else if case .needsYouHelpWrite = path.last { path.removeLast() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
