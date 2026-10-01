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
                            .tint(OutreachTheme.accent)
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
            }
        }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.contactName).font(.headline)
                Spacer()
                if let date = item.repliedDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !item.companyName.isEmpty {
                Text(item.companyName).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(item.reasonLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OutreachTheme.accent)
            let preview = item.replyText.isEmpty ? item.replySummary : item.replyText
            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
