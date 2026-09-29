import SwiftUI

/// One synced message: who it's from, what TODD read in it, the full text,
/// and a short reply sent from the connected mailbox - prefilled with
/// TODD's draft when there is one.
struct MessageDetailView: View {
    let apiClient: OutreachAPIClient
    let mailboxId: String
    let messageId: String

    @Environment(\.dismiss) private var dismiss
    @State private var message: MailboxMessage?
    @State private var replySubject = ""
    @State private var replyBody = ""
    @State private var isSending = false
    @State private var status: String?
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false
    @FocusState private var isReplyFocused: Bool

    var body: some View {
        ScrollView {
            if let message {
                VStack(alignment: .leading, spacing: 16) {
                    header(message)
                    if let summary = message.signalSummary ?? message.recommendedAction, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("What TODD sees", systemImage: "sparkles")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(OutreachTheme.accent)
                            Text(summary).font(.subheadline)
                            if let action = message.recommendedAction, action != summary, !action.isEmpty {
                                Text(action).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OutreachTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Text(message.bodyText)
                        .font(.body)
                        .textSelection(.enabled)
                    Divider()
                    replySection
                }
                .padding(20)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(message?.displaySubject ?? "Message")
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
        VStack(alignment: .leading, spacing: 6) {
            Text(message.displaySubject).font(.title3.bold())
            Text(message.sender).font(.subheadline.weight(.semibold))
            if let email = message.fromEmail, email != message.sender {
                Text(email).font(.caption).foregroundStyle(.secondary)
            }
            if let date = message.receivedDate {
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var replySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reply").font(.headline)
            TextField("Subject", text: $replySubject)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.15)))
            TextField("Write a short reply", text: $replyBody, axis: .vertical)
                .lineLimit(4...12)
                .focused($isReplyFocused)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.15)))
            if let status {
                Text(status).font(.footnote).foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            Button {
                Task { await send() }
            } label: {
                Text(isSending ? "Sending..." : "Send reply")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OutreachTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(isSending || replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func load() async {
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
