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
    @State private var filter: DraftFilter = .all

    private enum DraftFilter: Hashable { case all, replies, followUps }

    private var visibleItems: [DraftItem] {
        switch filter {
        case .all: return store.items
        case .replies: return store.items.filter(\.isReply)
        case .followUps: return store.items.filter { !$0.isReply }
        }
    }

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                HStack {
                    FilterChips(selection: $filter, options: [(.all, "All"), (.replies, "Replies"), (.followUps, "Follow-ups")])
                    Text("\(store.items.count) waiting").font(.system(size: 13)).foregroundStyle(Ink.muted).fixedSize()
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
                if store.rewritingCount > 0 {
                    Label("Maya is rewriting \(store.rewritingCount) draft\(store.rewritingCount == 1 ? "" : "s") you sent back.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.muted)
                        .padding(.horizontal, 4)
                }
                if let resultMessage {
                    Label(resultMessage, systemImage: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Tint.green.foreground)
                }
                if let errorMessage {
                    Text(errorMessage).font(.system(size: 13)).foregroundStyle(Ink.danger)
                }
                ForEach(visibleItems) { item in
                    let isSelected = selection.contains(item.id)
                    Button {
                        if isSelecting {
                            if isSelected { selection.remove(item.id) } else { selection.insert(item.id) }
                        } else {
                            path.append(.draftDetail(item))
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            if isSelecting {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(isSelected ? Area.drafts.tint.foreground : Ink.muted)
                            }
                            DraftRow(item: item)
                        }
                        .padding(12)
                        .background(isSelected ? Area.drafts.tint.background : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.bg)
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.contactName).font(.system(size: 16, weight: .bold)).lineLimit(1)
                if item.isReply { TagPill(text: "Reply", tint: Area.drafts.tint) }
                Spacer()
                if let date = item.updatedDate {
                    Text(date.shortAge).font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
            }
            if !item.companyName.isEmpty {
                Text(item.companyName).font(.system(size: 13)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            Text(item.subject).font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.text).lineLimit(1).padding(.top, 2)
            Text(item.preview).font(.system(size: 13)).foregroundStyle(Ink.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension DraftItem {
    var updatedDate: Date? { ISO8601DateFormatter.flexible(updatedAt) }

    /// The body as text - drafts are HTML.
    var preview: String {
        CatalystText.plainText(fromHTML: body).replacingOccurrences(of: "\n", with: " ")
    }
}

extension Date {
    /// "8h", "3d", "now" - the age shown on list rows.
    var shortAge: String {
        let seconds = max(0, Date().timeIntervalSince(self))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(86400 * 7): return "\(Int(seconds / 86400))d"
        default: return formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
