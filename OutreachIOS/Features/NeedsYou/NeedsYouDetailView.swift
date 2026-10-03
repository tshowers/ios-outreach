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
                    TODDNote(label: "Maya's read", text: item.replySummary)
                }
                if !item.readableReply.isEmpty { messageCard }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.bg)
        .safeAreaInset(edge: .bottom) { StickyActionBar { actions } }
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
                    Text(item.companyName).font(.subheadline).foregroundStyle(Ink.muted)
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
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .tint(Area.needsYou.tint.foreground)
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
        let tint = Area.needsYou.tint
        return TintCard(tint: tint, radius: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Why it needs you", color: tint.foreground)
                Text(why.title).font(.system(size: 20, weight: .bold)).tracking(-0.3)
                Text(why.detail).font(.system(size: 15))
                Text(why.suggestion).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint.foreground)
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
                            .foregroundStyle(Ink.muted)
                    }
                }
                if !item.lastSubject.isEmpty {
                    Text(item.replySubject).font(.caption).foregroundStyle(Ink.muted)
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
                            .foregroundStyle(Ink.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                    .font(.subheadline)
                    .tint(Ink.muted)
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            if item.kind.needsNoAnswer {
                doneButton(prominent: true)
                replyButton(title: "Reply anyway", useMayaDraft: false, prominent: false)
            } else {
                if item.hasMayaDraft {
                    replyButton(title: "Review Maya's reply", useMayaDraft: true, prominent: true)
                    HStack(spacing: 8) {
                        replyButton(title: "Write my own", useMayaDraft: false, prominent: false)
                        doneButton(prominent: false)
                    }
                } else {
                    replyButton(title: "Write a reply", useMayaDraft: false, prominent: true)
                    doneButton(prominent: false)
                }
            }
        }
    }

    private func replyButton(title: String, useMayaDraft: Bool, prominent: Bool) -> some View {
        Button {
            path.append(.needsYouReply(item, useMayaDraft: useMayaDraft))
        } label: {
            Label(title, systemImage: useMayaDraft ? "sparkles" : "square.and.pencil")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pill(prominent ? .primary : .secondary, height: prominent ? 52 : 44))
    }

    private func doneButton(prominent: Bool) -> some View {
        Button {
            Task { await markDone() }
        } label: {
            Label(isMarkingDone ? "Marking done…" : "Mark as done", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pill(prominent ? .primary : .secondary, height: prominent ? 52 : 44))
        .disabled(isMarkingDone)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
