import SwiftUI

/// What Home shows. nil counts are still loading.
struct HomeModel {
    var userName: String
    /// An inbox the last sync couldn't reach.
    var brokenMailbox: String?
    /// Everyone waiting on you, newest first; nil while loading.
    var needsYouNames: [String]?
    var draftsCount: Int?
    var draftsDetail: String
    var inboxNewCount: Int?
    var catalystCount: Int?
    var activityDetail: String
    var summary: SignalEngineSummary
}

struct HomeActions {
    var reconnect: () -> Void
    var needsYou: () -> Void
    var startNeedsYou: () -> Void
    var drafts: () -> Void
    var inbox: () -> Void
    var catalyst: () -> Void
    var activity: () -> Void
}

/// Home (design 4a): the logo header, a reconnect strip when an inbox is
/// down, the pink Needs You hero, four area tiles and the pipeline figures.
struct HomeDashboard<AccountMenu: View, Footer: View>: View {
    let model: HomeModel
    let actions: HomeActions
    @ViewBuilder var accountMenu: AccountMenu
    @ViewBuilder var footer: Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let mailbox = model.brokenMailbox { reconnectStrip(mailbox) }
                needsYouHero
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile(.drafts, symbol: "square.and.pencil", count: model.draftsCount, title: "Drafts", detail: model.draftsDetail, action: actions.drafts)
                    tile(.inbox, symbol: "tray", count: model.inboxNewCount, title: "Inbox", detail: "new today", action: actions.inbox)
                    tile(.catalyst, symbol: "bolt", count: model.catalystCount, title: "Catalyst", detail: "contacts gone quiet", action: actions.catalyst)
                    tile(.activity, symbol: "waveform.path.ecg", count: nil, title: "Activity", detail: model.activityDetail, action: actions.activity)
                }
                pipeline
                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("OutreachLogo")
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Outreach")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Ink.text)
            Spacer()
            Menu {
                accountMenu
            } label: {
                Text(InitialsBadge.initials(model.userName))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Ink.text)
                    .frame(width: 40, height: 40)
                    .background(Ink.surface, in: Circle())
            }
            .accessibilityLabel("Account menu")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func reconnectStrip(_ address: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 1) {
                Text("Can't reach")
                Text(address).lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Button("Reconnect", action: actions.reconnect)
                .buttonStyle(.pill(.dark, height: 34))
        }
        .foregroundStyle(Tint.yellow.foreground)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Tint.yellow.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var needsYouHero: some View {
        let tint = Area.needsYou.tint
        let names = model.needsYouNames ?? []
        return TintCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Needs you", color: tint.foreground)
                        Text(needsYouLine)
                            .font(.system(size: 15))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Text(model.needsYouNames == nil ? "–" : "\(names.count)")
                        .font(.system(size: 56, weight: .bold))
                        .tracking(-2)
                        .monospacedDigit()
                }
                if !names.isEmpty {
                    HStack {
                        HStack(spacing: -3) {
                            ForEach(Array(names.prefix(5).enumerated()), id: \.offset) { _, name in
                                Text(InitialsBadge.initials(name))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Ink.text)
                                    .frame(width: 32, height: 32)
                                    .background(Ink.bg, in: Circle())
                                    .overlay(Circle().stroke(tint.background, lineWidth: 2))
                            }
                        }
                        .accessibilityHidden(true)
                        Spacer()
                        Button(action: actions.startNeedsYou) {
                            HStack(spacing: 6) {
                                Text("Start")
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            }
                        }
                        .buttonStyle(.pill(.dark, height: 40))
                    }
                }
            }
            .foregroundStyle(tint.foreground)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture(perform: actions.needsYou)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Needs you, \(names.count) waiting")
    }

    private var needsYouLine: String {
        guard let names = model.needsYouNames else { return "Checking who's waiting on you…" }
        guard let first = names.first else { return "You're all caught up." }
        let others = names.count - 1
        return others > 0 ? "\(first) and \(others) more are waiting on you." : "\(first) is waiting on you."
    }

    private func tile(_ area: Area, symbol: String, count: Int?, title: String, detail: String, action: @escaping () -> Void) -> some View {
        let tint = area.tint
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    if let count {
                        Text("\(count)").font(.system(size: 24, weight: .bold)).monospacedDigit()
                    }
                }
                Spacer(minLength: 28)
                Text(title).font(.system(size: 17, weight: .bold))
                Text(detail)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(tint.foreground)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .background(tint.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var pipeline: some View {
        let summary = model.summary
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Pipeline")
                    Spacer()
                    (Text("Sending now ").foregroundStyle(Ink.muted) + Text("\(summary.sending)").bold().foregroundStyle(Ink.text))
                        .font(.system(size: 12))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                    figure(summary.activeThreads, "Active threads", Ink.blue)
                    figure(summary.draftReady, "Draft ready", Ink.violet)
                    figure(summary.stalledWaiting, "Stalled", Ink.yellow)
                    figure(summary.hotLeads, "Hot leads", Ink.pink)
                    figure(summary.warmLeads, "Warm leads", Ink.surface2)
                    figure(summary.queuedActions, "Queued", Ink.cyan)
                }
            }
        }
    }

    private func figure(_ value: Int, _ label: String, _ dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text("\(value)").font(.system(size: 19, weight: .bold)).monospacedDigit().foregroundStyle(Ink.text)
            }
            Text(label).font(.system(size: 12)).foregroundStyle(Ink.muted)
        }
    }
}
