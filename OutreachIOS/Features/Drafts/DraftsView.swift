import SwiftUI

/// Maya's drafts waiting for a decision. Tap one to read, edit and approve
/// it; Select to approve or send back several at once.
struct DraftsView: View {
    @ObservedObject var store: DraftsStore
    @Binding var path: [OutreachRoute]
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var isWorking = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView()
            } else if let error = store.errorMessage, store.items.isEmpty {
                ContentUnavailableView("Couldn't load Drafts", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if store.items.isEmpty {
                ContentUnavailableView {
                    Label("No drafts waiting", systemImage: "tray")
                } description: {
                    Text(store.rewritingCount > 0 ? "Maya is rewriting \(store.rewritingCount) - they'll be back here soon." : "When Maya drafts an email for your approval, it shows up here.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Cancel" : "Select") {
                        isSelecting.toggle()
                        selection.removeAll()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                batchBar
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private var list: some View {
        List {
            if store.rewritingCount > 0 {
                Label("Maya is rewriting \(store.rewritingCount) draft\(store.rewritingCount == 1 ? "" : "s") you sent back.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            ForEach(store.items) { item in
                Button {
                    if isSelecting {
                        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                    } else {
                        path.append(.draftDetail(item))
                    }
                } label: {
                    HStack(spacing: 12) {
                        if isSelecting {
                            Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selection.contains(item.id) ? OutreachTheme.accent : .secondary)
                        }
                        DraftRow(item: item)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    private var batchBar: some View {
        VStack(spacing: 8) {
            Button(selection.count == store.items.count ? "Deselect All" : "Select All") {
                selection = selection.count == store.items.count ? [] : Set(store.items.map(\.id))
            }
            .font(.footnote)
            HStack(spacing: 12) {
                Button {
                    Task { await rewriteSelected() }
                } label: {
                    Label("Rewrite \(selection.count)", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await approveSelected() }
                } label: {
                    Label("Approve \(selection.count)", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(OutreachTheme.accent)
            }
            .controlSize(.large)
            .disabled(selection.isEmpty || isWorking)
        }
        .padding()
        .background(.bar)
    }

    private func approveSelected() async {
        isWorking = true
        errorMessage = nil
        let ids = store.items.map(\.id).filter(selection.contains)
        do {
            let approved = try await store.approve(contactIds: ids)
            resultMessage = approved == ids.count ? "Approved \(approved). They're in the Outbox." : "Approved \(approved) of \(ids.count). The rest are still here."
            selection.removeAll()
            isSelecting = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func rewriteSelected() async {
        isWorking = true
        errorMessage = nil
        let ids = store.items.map(\.id).filter(selection.contains)
        do {
            let queued = try await store.rewrite(contactIds: ids)
            resultMessage = "Sent \(queued) back to Maya to rewrite."
            selection.removeAll()
            isSelecting = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

struct DraftRow: View {
    let item: DraftItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.contactName).font(.headline)
                if item.isReply {
                    Text("Reply")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OutreachTheme.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(OutreachTheme.accent)
                }
            }
            if !item.companyName.isEmpty {
                Text(item.companyName).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(item.subject).font(.subheadline.weight(.medium)).lineLimit(1)
            Text(item.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
