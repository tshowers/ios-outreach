import SwiftUI

/// Needs you (design 5a): everyone waiting on a decision from you, split
/// into "needs an answer" and "nothing to answer". The goal is zero (5d).
struct NeedsYouView: View {
    @ObservedObject var store: NeedsYouStore
    @Binding var path: [OutreachRoute]
    /// Plan lives on the web for now.
    var openPlan: (() -> Void)?

    private let pink = Area.needsYou.tint

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView()
            } else if let error = store.errorMessage, store.items.isEmpty {
                ContentUnavailableView("Couldn't load Needs you", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if store.items.isEmpty {
                NeedsYouZeroView(planCount: store.planCount, onSeePlan: openPlan)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg)
        .overlay(alignment: .bottom) { NeedsYouToast(store: store) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Needs you").font(.system(size: 30, weight: .bold)).tracking(-0.5)
                        Text("\(store.answerItems.count) need\(store.answerItems.count == 1 ? "s" : "") an answer · \(store.clearItems.count) to clear")
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    Text("\(store.items.count)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Ink.pink)
                        .monospacedDigit()
                }
                .padding(.bottom, 8)

                if !store.answerItems.isEmpty {
                    Eyebrow(text: "Needs an answer").padding(.top, 4)
                    ForEach(store.answerItems) { item in row(item, answer: true) }
                }
                if !store.clearItems.isEmpty {
                    HStack {
                        Eyebrow(text: "Nothing to answer")
                        Spacer()
                        Button(store.clearItems.count == 2 ? "Mark both done" : "Mark all done") {
                            store.markDoneWithUndo(store.clearItems)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ink.blueInk)
                    }
                    .padding(.top, 12)
                    ForEach(store.clearItems) { item in row(item, answer: false) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 80)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ item: NeedsYouItem, answer: Bool) -> some View {
        Button {
            path.append(.needsYouDetail(item))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                InitialsBadge(name: item.contactName, tint: answer ? pink : .neutral, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.contactName).font(.system(size: 16, weight: .bold)).lineLimit(1)
                        Spacer()
                        if let date = item.repliedDate {
                            Text(date.shortAge).font(.system(size: 12)).foregroundStyle(Ink.muted)
                        }
                    }
                    HStack(spacing: 4) {
                        TagPill(text: item.kindLabel, tint: item.kind.tint)
                        if item.hasMayaDraft { TagPill(text: "Maya drafted", tint: .green) }
                    }
                    if !item.listPreview.isEmpty {
                        Text(item.listPreview)
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.markDoneWithUndo([item]) } label: { Label("Mark as done", systemImage: "checkmark") }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Cleared to zero (5d).
struct NeedsYouZeroView: View {
    let planCount: Int?
    let onSeePlan: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Tint.green.foreground)
                .frame(width: 96, height: 96)
                .background(Tint.green.background, in: Circle())
            Text("Nobody's waiting on you")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            Text(planCount.map { "Maya is running \($0) conversation\($0 == 1 ? "" : "s") on her own. You'll see someone here as soon as they reply." }
                 ?? "You'll see someone here as soon as they reply.")
                .font(.system(size: 16))
                .foregroundStyle(Ink.muted)
                .multilineTextAlignment(.center)
            if let planCount, let onSeePlan {
                Button("See Plan · \(planCount)", action: onSeePlan)
                    .font(.system(size: 15, weight: .bold))
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .foregroundStyle(Tint.violet.foreground)
                    .background(Tint.violet.background, in: Capsule())
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}

/// "Marked Dana done · Undo", for five seconds.
struct NeedsYouToast: View {
    @ObservedObject var store: NeedsYouStore

    var body: some View {
        if let toast = store.toast {
            HStack {
                Text(toast.text).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Spacer(minLength: 12)
                if toast.canUndo {
                    Button {
                        store.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(Color(hex: 0x0f1115))
                            .background(Color.white, in: Capsule())
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color(hex: 0x0f1115), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.snappy, value: toast.text)
        }
    }
}
