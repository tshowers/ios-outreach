import SwiftUI

/// Everyone waiting on you: replies that came in and threads Maya handed
/// back. Swipe right to reply, left for Done; tap for the whole thing.
struct NeedsYouView: View {
    @ObservedObject var store: NeedsYouStore
    @Binding var path: [OutreachRoute]
    @State private var actionError: String?

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView()
            } else if let error = store.errorMessage, store.items.isEmpty {
                ContentUnavailableView("Couldn't load Needs You", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if store.items.isEmpty {
                ContentUnavailableView("You're all caught up", systemImage: "checkmark.circle", description: Text("When someone replies or Maya needs you, they'll show up here."))
            } else {
                List {
                    if let actionError {
                        Text(actionError).font(.footnote).foregroundStyle(.red)
                    }
                    ForEach(store.items) { item in
                        Button {
                            path.append(.needsYouDetail(item))
                        } label: {
                            NeedsYouRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                path.append(.needsYouReply(item, useMayaDraft: item.hasMayaDraft))
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }
                            .tint(Ink.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await markDone(item) }
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(.gray)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Ink.bg)
        .navigationTitle("Needs You")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private func markDone(_ item: NeedsYouItem) async {
        do {
            try await store.markDone(item)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct NeedsYouRow: View {
    let item: NeedsYouItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NeedsYouAvatar(item: item)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.contactName).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = item.repliedDate {
                        Text(date.shortAge)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.muted)
                    }
                }
                if !item.companyName.isEmpty {
                    Text(item.companyName)
                        .font(.subheadline)
                        .foregroundStyle(Ink.muted)
                        .lineLimit(1)
                        .padding(.top, -4)
                }
                HStack(spacing: 6) {
                    ForEach(item.pills, id: \.label) { $0 }
                }
                if !item.listPreview.isEmpty {
                    Text(item.listPreview)
                        .font(.subheadline)
                        .foregroundStyle(Ink.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
