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
    @State private var filter: InboxFilter = .all

    private enum InboxFilter: Hashable { case all, replies, autoReplies, bounces }

    private var visibleMessages: [MailboxMessage] {
        switch filter {
        case .all: return messages
        case .replies: return messages.filter { [.reply, .forward].contains($0.kind) }
        case .autoReplies: return messages.filter { $0.kind == .outOfOffice }
        case .bounces: return messages.filter { $0.kind == .bounce }
        }
    }

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
        .background(Ink.bg)
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The mailbox and when it last synced, under the title (4e).
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Inbox").font(.system(size: 15, weight: .bold))
                    if let mailbox = selectedMailbox {
                        Text(syncLine(mailbox)).font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
                    }
                }
            }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                FilterChips(selection: $filter, options: [(.all, "All"), (.replies, "Replies"), (.autoReplies, "Auto-replies"), (.bounces, "Bounces")])
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 13)).foregroundStyle(Ink.danger).padding(.horizontal, 16)
                }
                if store.isLoadingFirstMessages {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading messages…").foregroundStyle(Ink.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else if visibleMessages.isEmpty {
                    Text(isSyncing ? "Syncing…" : (filter == .all ? "No recent messages. Pull down to check for new mail." : "Nothing here right now."))
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(visibleMessages) { message in
                        NavigationLink(value: OutreachRoute.message(mailboxId: message.mailboxId ?? selectedMailbox?.id ?? "", messageId: message.id)) {
                            MessageRow(message: message)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
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

    /// "ty@taliferro.tech · 8 min ago"
    private func syncLine(_ mailbox: MailboxSummary) -> String {
        var parts = [mailbox.emailAddress]
        if store.isRefreshing || isSyncing {
            parts.append("Updating…")
        } else if let lastSyncAt = mailbox.lastSyncAt, let date = ISO8601DateFormatter.flexible(lastSyncAt) {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

private struct MessageRow: View {
    let message: MailboxMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.unread == true ? Ink.blue : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.sender)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Spacer()
                    if let date = message.receivedDate {
                        Text(date.shortAge).font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                }
                Text(message.displaySubject)
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    TagPill(text: message.kind.label, tint: message.kind.tint)
                    Text(message.summaryLine)
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
