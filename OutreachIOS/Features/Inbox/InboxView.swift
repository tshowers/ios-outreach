import SwiftUI

/// The native twin of outreach.taliferro.tech/inbox-access: the connected
/// inbox's synced messages (who replied, what TODD thinks it means), a
/// mailbox switcher, Sync, and connecting another inbox. Reading is free;
/// connecting and replying need the subscription (the backend checks).
struct InboxView: View {
    @ObservedObject var store: InboxStore
    let defaultEmail: String
    @Binding var path: [OutreachRoute]

    @State private var isConfirmingDisconnect = false

    private var mailboxes: [MailboxSummary] { store.mailboxes }
    private var selectedMailbox: MailboxSummary? { store.selectedMailbox }
    private var messages: [MailboxMessage] { store.messages }
    private var isSyncing: Bool { store.isSyncing }
    private var errorMessage: String? { store.errorMessage }

    var body: some View {
        Group {
            if !store.hasLoadedMailboxes {
                ProgressView()
            } else if mailboxes.isEmpty {
                notConnected
            } else {
                messageList
            }
        }
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let mailbox = selectedMailbox {
                ToolbarItem(placement: .topBarTrailing) { mailboxMenu(mailbox) }
            }
        }
        .task { await store.refreshIfStale() }
        .refreshable { await store.sync() }
        .confirmationDialog("Disconnect \(selectedMailbox?.emailAddress ?? "this inbox")?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await store.disconnect() } }
        } message: {
            Text("Outreach stops seeing replies from this inbox. You can connect it again any time.")
        }
    }

    // MARK: - States

    private var notConnected: some View {
        ContentUnavailableView {
            Label("Connect your inbox", systemImage: "tray")
        } description: {
            Text("Outreach needs to see replies to tell you who answered and who to follow up with next.")
        } actions: {
            Button("Connect an inbox") { path.append(.connect(email: defaultEmail, provider: MailProvider.detect(from: defaultEmail))) }
                .buttonStyle(.borderedProminent)
                .tint(OutreachTheme.accent)
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var messageList: some View {
        List {
            if let mailbox = selectedMailbox {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mailbox.emailAddress).font(.headline)
                        Text(syncLine(mailbox)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            Section("Recent") {
                if store.isLoadingFirstMessages {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading messages…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                } else if messages.isEmpty {
                    Text(isSyncing ? "Syncing…" : "No recent messages. Pull down to check for new mail.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(messages) { message in
                        NavigationLink(value: OutreachRoute.message(mailboxId: message.mailboxId ?? selectedMailbox?.id ?? "", messageId: message.id)) {
                            MessageRow(message: message)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func mailboxMenu(_ mailbox: MailboxSummary) -> some View {
        Menu {
            Button {
                Task { await store.sync() }
            } label: {
                Label(isSyncing ? "Syncing..." : "Sync now", systemImage: "arrow.clockwise")
            }
            .disabled(isSyncing)
            if mailboxes.count > 1 {
                Section("Inboxes") {
                    ForEach(mailboxes) { box in
                        Button {
                            Task { await store.select(box.id) }
                        } label: {
                            Label(box.emailAddress, systemImage: box.id == mailbox.id ? "checkmark" : "tray")
                        }
                    }
                }
                if mailbox.isPrimary != true {
                    Button {
                        Task { await store.makePrimary(mailbox) }
                    } label: {
                        Label("Make primary", systemImage: "star")
                    }
                }
            }
            Button {
                path.append(.connect(email: "", provider: .gmail))
            } label: {
                Label("Add another inbox", systemImage: "plus")
            }
            Button(role: .destructive) {
                isConfirmingDisconnect = true
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Inbox options")
    }

    private func syncLine(_ mailbox: MailboxSummary) -> String {
        var parts = [mailbox.subtitle]
        if store.isRefreshing || isSyncing {
            parts.append("Updating…")
        } else if let lastSyncAt = mailbox.lastSyncAt, let date = ISO8601DateFormatter.flexible(lastSyncAt) {
            parts.append("Synced \(date.formatted(.relative(presentation: .named)))")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct MessageRow: View {
    let message: MailboxMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.unread == true ? OutreachTheme.accent : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(message.sender)
                        .font(.subheadline.weight(message.unread == true ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let date = message.receivedDate {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message.displaySubject)
                    .font(.subheadline)
                    .lineLimit(1)
                if let preview = message.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let classification = message.classification, !classification.isEmpty {
                        Tag(text: classification.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                    if message.replied == true {
                        Tag(text: "Replied")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(OutreachTheme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(OutreachTheme.accent)
    }
}

extension ISO8601DateFormatter {
    /// Parses timestamps with or without fractional seconds.
    static func flexible(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
