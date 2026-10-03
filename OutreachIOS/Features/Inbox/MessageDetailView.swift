import SwiftUI

/// One synced message: who it's from, what TODD read in it, the full text,
/// and a short reply sent from the connected mailbox - prefilled with
/// TODD's draft when there is one.
struct MessageDetailView: View {
    let apiClient: OutreachAPIClient
    let mailboxId: String
    let messageId: String
    /// DesignGallery: show this message instead of fetching one.
    var sample: MailboxMessage?

    @Environment(\.dismiss) private var dismiss
    @State private var message: MailboxMessage?
    @State private var replySubject = ""
    @State private var replyBody = ""
    @State private var isSending = false
    @State private var status: String?
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false
    @State private var isShowingOriginal = false
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        ScrollView {
            if let message {
                VStack(alignment: .leading, spacing: 16) {
                    header(message)
                    if let summary = message.signalSummary, !summary.isEmpty {
                        TODDNote(label: "What TODD sees", text: summary) {
                            if let action = message.recommendedAction?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty, action != summary {
                                Text(action)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Ink.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Ink.bg, in: Capsule())
                            }
                        }
                    }
                    bodyText(message)
                    replySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(Ink.danger).padding()
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .background(Ink.bg)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { isConfirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isReplyFocused = false }
            }
        }
        .confirmationDialog("Delete this message?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
        .task { await load() }
    }

    private func header(_ message: MailboxMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.displaySubject)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                InitialsBadge(name: message.sender, tint: .blue, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.sender).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text([message.fromEmail != message.sender ? message.fromEmail : nil, message.receivedDate?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                }
                Spacer()
                TagPill(text: message.kind.label, tint: message.kind.tint)
            }
        }
    }

    /// The message without links, headers and the quoted thread; the
    /// original is one tap away.
    @ViewBuilder
    private func bodyText(_ message: MailboxMessage) -> some View {
        let clean = MessageText.clean(message.bodyText)
        Text(clean.isEmpty ? message.bodyText : clean)
            .font(.system(size: 16))
            .lineSpacing(4)
            .foregroundStyle(Ink.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        if !clean.isEmpty, clean != message.bodyText.trimmingCharacters(in: .whitespacesAndNewlines) {
            DisclosureGroup("Original email", isExpanded: $isShowingOriginal) {
                Text(message.bodyText)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            .font(.system(size: 14, weight: .semibold))
            .tint(Ink.muted)
        }
    }

    private var replySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reply").font(.system(size: 15, weight: .bold))
            VStack(alignment: .leading, spacing: 10) {
                TextField("Subject", text: $replySubject)
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.muted)
                Divider()
                TextField("Write a short reply", text: $replyBody, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(4...12)
                    .focused($isReplyFocused)
                HStack {
                    if let status {
                        Label(status, systemImage: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Tint.green.foreground)
                    } else if let errorMessage {
                        Text(errorMessage).font(.system(size: 13)).foregroundStyle(Ink.danger)
                    }
                    Spacer()
                    Button {
                        Task { await send() }
                    } label: {
                        Label(isSending ? "Sending…" : "Send reply", systemImage: "paperplane")
                    }
                    .buttonStyle(.pill(.primary, height: 44))
                    .disabled(isSending || replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func load() async {
        if let sample {
            message = sample
            replySubject = "Re: \(sample.displaySubject)"
            return
        }
        do {
            let loaded = try await apiClient.fetchMessage(mailboxId: mailboxId, messageId: messageId)
            message = loaded
            replySubject = loaded.replyDraftSubject?.isEmpty == false
                ? loaded.replyDraftSubject!
                : (loaded.displaySubject.lowercased().hasPrefix("re:") ? loaded.displaySubject : "Re: \(loaded.displaySubject)")
            if replyBody.isEmpty { replyBody = loaded.replyDraftBody ?? "" }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        status = nil
        defer { isSending = false }
        do {
            try await apiClient.reply(mailboxId: mailboxId, messageId: messageId, subject: replySubject, body: replyBody)
            status = "Sent from your inbox."
            replyBody = ""
            isReplyFocused = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        do {
            try await apiClient.deleteMessage(mailboxId: mailboxId, messageId: messageId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
