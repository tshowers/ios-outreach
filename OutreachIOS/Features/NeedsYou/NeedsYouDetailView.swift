import SwiftUI

/// One person waiting on you (design 5b, 5c): a pager across everyone
/// waiting, why they're here in plain words (or when they're back, for an
/// away message), what they said and Maya's reply, and the obvious next step
/// in a sticky bar. Done or sent, the next person takes their place.
struct NeedsYouDetailView: View {
    @ObservedObject var store: NeedsYouStore
    @Binding var path: [OutreachRoute]
    @Environment(\.openURL) private var openURL
    @State private var currentId: String
    @State private var isShowingOriginal = false

    private let pink = Area.needsYou.tint

    init(item: NeedsYouItem, store: NeedsYouStore, path: Binding<[OutreachRoute]>) {
        self.store = store
        _path = path
        _currentId = State(initialValue: item.contactId)
    }

    private var items: [NeedsYouItem] { store.ordered }
    private var index: Int? { items.firstIndex { $0.contactId == currentId } }
    private var item: NeedsYouItem? { index.map { items[$0] } }

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        person(item)
                        if item.kind == .outOfOffice { awayCard(item) } else { whyCard(item) }
                        said(item)
                        if item.hasMayaDraft { mayaReply(item) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .top) { pager }
                .safeAreaInset(edge: .bottom) { actionBar(item) }
            } else {
                NeedsYouZeroView(planCount: store.planCount, onSeePlan: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.bg)
        .overlay(alignment: .bottom) { NeedsYouToast(store: store).padding(.bottom, 150) }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: currentId) { _, _ in isShowingOriginal = false }
        .onChange(of: store.items.map(\.contactId)) { _, ids in
            // Done, sent or undone elsewhere: keep showing someone who's here.
            if !ids.contains(currentId), let next = items.first { currentId = next.contactId }
        }
    }

    // MARK: - Pager

    private var pager: some View {
        let previous = index.flatMap { $0 > 0 ? items[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < items.count ? items[$0 + 1] : nil }
        return HStack {
            circle("chevron.left", label: "Back") { close() }
            Spacer()
            if let index {
                (Text("\(index + 1)").bold() + Text(" of \(items.count)").foregroundColor(Ink.muted))
                    .font(.system(size: 14))
            }
            Spacer()
            HStack(spacing: 8) {
                circle("chevron.up", label: "Previous") { if let previous { currentId = previous.contactId } }
                    .disabled(previous == nil).opacity(previous == nil ? 0.35 : 1)
                circle("chevron.down", label: "Next") { if let next { currentId = next.contactId } }
                    .disabled(next == nil).opacity(next == nil ? 0.35 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Ink.bg)
    }

    private func circle(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: 44, height: 44)
                .background(Ink.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Content

    private func person(_ item: NeedsYouItem) -> some View {
        HStack(spacing: 12) {
            InitialsBadge(name: item.contactName, tint: item.needsAnswer ? pink : .neutral, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.contactName).font(.system(size: 22, weight: .bold)).tracking(-0.3)
                Text([item.companyName.isEmpty ? nil : item.companyName, item.repliedDate.map { "replied \($0.shortAge) ago" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 8)
            TagPill(text: item.kind.label, tint: item.kind.tint)
        }
    }

    private func whyCard(_ item: NeedsYouItem) -> some View {
        (Text("Why it's here. ").bold() + Text(item.whyItsHere))
            .font(.system(size: 15))
            .foregroundStyle(pink.foreground)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pink.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func awayCard(_ item: NeedsYouItem) -> some View {
        let away = item.outOfOffice
        return HStack(spacing: 14) {
            if let date = away.returnDate {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Ink.pink)
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Ink.text)
                }
                .frame(width: 48, height: 52)
                .background(Ink.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(away.returnDate.map { "Out of office until \($0.formatted(.dateTime.weekday(.wide)))" } ?? "Out of office")
                    .font(.system(size: 17, weight: .bold))
                Text(away.alternate.isEmpty ? "Nothing to answer." : "Nothing to answer. \(away.alternate) covers anything urgent.")
                    .font(.system(size: 14))
            }
        }
        .foregroundStyle(Tint.yellow.foreground)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tint.yellow.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func said(_ item: NeedsYouItem) -> some View {
        if !item.readableReply.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: item.kind == .automated ? "The email" : "What \(item.firstName) said")
                Text(item.readableReply)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.surface, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                HStack(alignment: .top) {
                    if !item.replySummary.isEmpty, item.replySummary != item.readableReply {
                        Label("Maya's read: \(item.replySummary)", systemImage: "sparkle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Tint.green.foreground)
                    }
                    Spacer()
                    if item.readableReply != item.replyText, !item.replyText.isEmpty {
                        Button(isShowingOriginal ? "Hide original" : "Original email") {
                            withAnimation { isShowingOriginal.toggle() }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ink.blueInk)
                    }
                }
                if isShowingOriginal {
                    Text(item.replyText)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.muted)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func mayaReply(_ item: NeedsYouItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Maya's reply")
            Text(CatalystText.plainText(fromHTML: item.mayaDraftBody))
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(Tint.blue.foreground)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tint.blue.background, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
                .padding(.leading, 32)
        }
    }

    // MARK: - Actions

    private func actionBar(_ item: NeedsYouItem) -> some View {
        let away = item.outOfOffice
        let canEmailAlternate = item.kind == .outOfOffice && !away.alternateEmail.isEmpty
        return StickyActionBar {
            primary(item)
            HStack(spacing: 8) {
                if canEmailAlternate {
                    secondary("Email \(away.alternate)", symbol: "envelope") {
                        if let url = URL(string: "mailto:\(away.alternateEmail)") { openURL(url) }
                    }
                } else {
                    secondary("Write my own", symbol: "square.and.pencil") { path.append(.needsYouReply(item, useMayaDraft: false)) }
                }
                if item.primaryAction != .markDone {
                    secondary("Mark as done", symbol: "checkmark") { store.markDoneWithUndo([item]) }
                }
            }
            HStack {
                contactLink("Call", symbol: "phone", url: phoneURL(item, "tel"))
                Spacer()
                contactLink("Text", symbol: "message", url: phoneURL(item, "sms"))
                Spacer()
                contactLink("Email", symbol: "envelope", url: item.email.isEmpty ? nil : URL(string: "mailto:\(item.email)"))
            }
            .padding(.horizontal, 32)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func primary(_ item: NeedsYouItem) -> some View {
        switch item.primaryAction {
        case .reviewMaya:
            Button { path.append(.needsYouReply(item, useMayaDraft: true)) } label: {
                Label("Review Maya's reply", systemImage: "paperplane").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillPrimary)
        case .helpWrite:
            Button { path.append(.needsYouHelpWrite(item)) } label: {
                Label("Help me write it", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillPrimary)
        case .connectInbox:
            Button { path = [.inbox] } label: {
                Label("Connect inbox", systemImage: "tray").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillPrimary)
        case .markDone:
            Button { store.markDoneWithUndo([item]) } label: {
                Label("Mark as done", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pillPrimary)
        }
    }

    private func secondary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).lineLimit(1).frame(maxWidth: .infinity)
        }
        .buttonStyle(.pill(.secondary, height: 44))
    }

    private func contactLink(_ title: String, symbol: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(Ink.blueInk)
        .disabled(url == nil)
        .opacity(url == nil ? 0.4 : 1)
    }

    private func phoneURL(_ item: NeedsYouItem, _ scheme: String) -> URL? {
        let digits = item.phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "\(scheme):\(digits)")
    }

    private func close() {
        store.commitPendingDone()
        if case .needsYouDetail = path.last { path.removeLast() }
    }
}
