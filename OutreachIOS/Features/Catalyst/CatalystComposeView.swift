import SwiftUI

/// One Catalyst email: TODD drafts it for this contact in the chosen tone,
/// you edit the subject and message, and send. The server builds the email
/// from its own records - recipient from the contact, sender from your
/// account - and Signal Engine takes over the thread after it goes out.
struct CatalystComposeView: View {
    let apiClient: OutreachAPIClient
    let contact: CatalystContact
    let onSent: (_ contactId: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tone: CatalystTone = .direct
    @State private var subject = ""
    @State private var message = ""
    @State private var isDrafting = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sentNote: String?
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tone").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Tone", selection: $tone) {
                        ForEach(CatalystTone.allCases) { tone in Text(tone.label).tag(tone) }
                    }
                    .pickerStyle(.segmented)
                    Text(tone.hint).font(.caption).foregroundStyle(.secondary)
                }

                if isDrafting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("TODD is drafting for \(contact.firstName)...").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                } else {
                    field("Subject") {
                        TextField("Subject", text: $subject)
                    }
                    field("Message") {
                        TextField("Message", text: $message, axis: .vertical)
                            .lineLimit(8...30)
                            .focused($isEditing)
                    }
                    Button {
                        Task { await draft() }
                    } label: {
                        Label("Redraft with TODD", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(OutreachTheme.accent)
                }

                if let sentNote {
                    Label(sentNote, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await send() }
                } label: {
                    Text(isSending ? "Sending..." : "Send to \(contact.firstName)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OutreachTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .disabled(isSending || isDrafting || sentNote != nil || subject.trimmingCharacters(in: .whitespaces).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Sent from your account. Signal Engine watches for opens and replies and takes over the follow-up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Catalyst")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
        .task { if subject.isEmpty && message.isEmpty { await draft() } }
        .onChange(of: tone) { _, _ in Task { await draft() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contact.fullName).font(.title2.bold())
            Text([contact.companyName, contact.email].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(contact.staleLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(contact.daysSinceLastContact >= 30 ? .orange : OutreachTheme.accent)
        }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.15)))
        }
    }

    private func draft() async {
        guard !isDrafting, sentNote == nil else { return }
        isDrafting = true
        errorMessage = nil
        defer { isDrafting = false }
        do {
            let draft = try await apiClient.draftCatalystEmail(contactId: contact.id, tone: tone)
            subject = draft.subject
            message = CatalystText.plainText(fromHTML: draft.bodyHtml)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let result = try await apiClient.sendCatalystEmail(contactId: contact.id, subject: subject, html: CatalystText.html(fromPlainText: message))
            sentNote = result.wasQueued
                ? "Queued. Catalyst paces sends during business hours."
                : "Sent to \(contact.firstName)."
            onSent(contact.id)
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The draft arrives as HTML (with the signature); it's edited here as
/// plain text and sent back as simple HTML paragraphs.
enum CatalystText {
    static func plainText(fromHTML html: String) -> String {
        let withBreaks = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</(p|div|li|h[1-6])>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        let stripped = withBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return decoded
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func html(fromPlainText text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return escaped
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined()
    }
}
