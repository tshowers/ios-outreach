import SwiftUI

/// One person waiting on you, laid out like a Contacts card: who it is and
/// how to reach them, why it's waiting on you in plain words, what they
/// said (readable, with the original email tucked away), and the next step -
/// the obvious one first.
struct NeedsYouDetailView: View {
    let item: NeedsYouItem
    @ObservedObject var store: NeedsYouStore
    @Binding var path: [OutreachRoute]
    @Environment(\.openURL) private var openURL
    @State private var isMarkingDone = false
    @State private var errorMessage: String?
    @State private var isShowingFullMessage = false
    @State private var isShowingOriginal = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                whyCard
                if !item.replySummary.isEmpty, item.replySummary != item.readableReply {
                    card {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Maya's read").font(.subheadline.weight(.semibold))
                                Text(item.replySummary).font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles").foregroundStyle(OutreachTheme.accent)
                        }
                    }
                }
                if !item.readableReply.isEmpty { messageCard }
                actions
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.firstName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            NeedsYouAvatar(item: item, size: 72)
            VStack(spacing: 2) {
                Text(item.contactName).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                if !item.companyName.isEmpty {
                    Text(item.companyName).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(item.pills, id: \.label) { $0 }
            }
            HStack(spacing: 12) {
                contactButton("message", title: "Text", url: phoneURL("sms"))
                contactButton("phone", title: "Call", url: phoneURL("tel"))
                contactButton("envelope", title: "Email", url: item.email.isEmpty ? nil : URL(string: "mailto:\(item.email)"))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func contactButton(_ symbol: String, title: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(width: 72, height: 56)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .tint(OutreachTheme.accent)
        .disabled(url == nil)
        .accessibilityLabel("\(title) \(item.firstName)")
    }

    private func phoneURL(_ scheme: String) -> URL? {
        let digits = item.phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "\(scheme):\(digits)")
    }

    // MARK: - Why

    private var whyCard: some View {
        let why = item.why
        return card {
            VStack(alignment: .leading, spacing: 6) {
                Text(why.title).font(.headline)
                Text(why.detail).font(.subheadline)
                Text(why.suggestion).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Their message

    private var messageCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.kind == .automated ? "The email" : "What \(item.firstName) said")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let date = item.repliedDate {
                        Text(date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !item.lastSubject.isEmpty {
                    Text(item.replySubject).font(.caption).foregroundStyle(.secondary)
                }
                Text(item.readableReply)
                    .font(.body)
                    .lineLimit(isShowingFullMessage ? nil : 8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.readableReply.count > 400 {
                    Button(isShowingFullMessage ? "Show Less" : "Show More") {
                        withAnimation { isShowingFullMessage.toggle() }
                    }
                    .font(.subheadline)
                    .tint(OutreachTheme.accent)
                }
                if item.readableReply != item.replyText, !item.replyText.isEmpty {
                    Divider()
                    DisclosureGroup("Original email", isExpanded: $isShowingOriginal) {
                        Text(item.replyText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .font(.subheadline)
                    .tint(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            if item.kind.needsNoAnswer {
                doneButton(prominent: true)
                replyButton(title: "Reply Anyway", useMayaDraft: false, prominent: false)
            } else {
                if item.hasMayaDraft {
                    replyButton(title: "Review Maya's Reply", useMayaDraft: true, prominent: true)
                    replyButton(title: "Write My Own", useMayaDraft: false, prominent: false)
                } else {
                    replyButton(title: "Write a Reply", useMayaDraft: false, prominent: true)
                }
                doneButton(prominent: false)
            }
        }
        .controlSize(.large)
        .padding(.top, 4)
    }

    private func replyButton(title: String, useMayaDraft: Bool, prominent: Bool) -> some View {
        Button {
            path.append(.needsYouReply(item, useMayaDraft: useMayaDraft))
        } label: {
            Label(title, systemImage: useMayaDraft ? "sparkles" : "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .prominence(prominent)
        .tint(OutreachTheme.accent)
    }

    private func doneButton(prominent: Bool) -> some View {
        Button {
            Task { await markDone() }
        } label: {
            Label(isMarkingDone ? "Marking Done…" : "Mark as Done", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity)
        }
        .prominence(prominent)
        .tint(prominent ? OutreachTheme.accent : .secondary)
        .disabled(isMarkingDone)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func markDone() async {
        isMarkingDone = true
        do {
            try await store.markDone(item)
            if path.last == .needsYouDetail(item) { path.removeLast() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isMarkingDone = false
    }
}

private extension View {
    /// The filled style for the screen's main action, bordered otherwise.
    @ViewBuilder
    func prominence(_ isProminent: Bool) -> some View {
        if isProminent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
