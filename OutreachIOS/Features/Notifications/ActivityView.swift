import SwiftUI

/// Everything Outreach and Maya told you about, newest first - including
/// what was held for quiet hours or switched off, so nothing is missed.
/// Grouped by day, with repeats of the same event merged ("Robert Leung
/// replied ×2"), each row with a chip in its area's colour (design 4b).
struct ActivityView: View {
    let apiClient: OutreachAPIClient
    let onOpen: (URL) -> Void
    /// DesignGallery: show these instead of fetching.
    var sample: [ActivityItem]?
    @State private var items: [ActivityItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView("Couldn't load activity", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "bell", description: Text("Replies, inbox problems and Maya's day show up here."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(ActivityGroup.byDay(items), id: \.title) { group in
                            Eyebrow(text: group.title)
                                .padding(.horizontal, 4)
                                .padding(.top, group.title == ActivityGroup.byDay(items).first?.title ? 0 : 12)
                            ForEach(group.rows) { row in
                                Button {
                                    if let route = row.item.route, let url = URL(string: route), !route.isEmpty { onOpen(url) }
                                } label: {
                                    rowView(row)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Ink.bg)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func rowView(_ row: ActivityRow) -> some View {
        let tint = row.item.tint
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint.foreground)
                .frame(width: 30, height: 30)
                .background(tint.background, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(row.count > 1 ? "\(row.item.title) ×\(row.count)" : row.item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.text)
                if let body = row.item.body.map({ MessageText.clean($0).replacingOccurrences(of: "\n", with: " ") }), !body.isEmpty {
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let date = row.item.date {
                Text(date.shortAge).font(.system(size: 12)).foregroundStyle(Ink.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private func load() async {
        if let sample {
            items = sample
            isLoading = false
            return
        }
        isLoading = true
        do {
            items = try await apiClient.fetchActivity()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// One row: an event, and how many times it repeated that day.
struct ActivityRow: Identifiable {
    let item: ActivityItem
    let count: Int
    var id: String { item.id }
}

/// A day's rows, "Today", "Yesterday" or the date.
struct ActivityGroup {
    let title: String
    let rows: [ActivityRow]

    /// Days newest first; within a day, the same title (and body) recorded
    /// more than once - e.g. a reply seen by two overlapping syncs - is one row.
    static func byDay(_ items: [ActivityItem], calendar: Calendar = .current) -> [ActivityGroup] {
        var groups: [(day: Date, rows: [ActivityRow])] = []
        for item in items {
            let day = calendar.startOfDay(for: item.date ?? .distantPast)
            if groups.last?.day != day { groups.append((day, [])) }
            var rows = groups[groups.count - 1].rows
            if let index = rows.firstIndex(where: { $0.item.title == item.title && $0.item.body == item.body }) {
                rows[index] = ActivityRow(item: rows[index].item, count: rows[index].count + 1)
            } else {
                rows.append(ActivityRow(item: item, count: 1))
            }
            groups[groups.count - 1].rows = rows
        }
        return groups.map { group in
            let title: String
            if calendar.isDateInToday(group.day) {
                title = "Today"
            } else if calendar.isDateInYesterday(group.day) {
                title = "Yesterday"
            } else {
                title = group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            }
            return ActivityGroup(title: title, rows: group.rows)
        }
    }
}

extension ActivityItem {
    /// The area colour for this kind of event.
    var tint: Tint {
        switch category {
        case "replies": return .blue
        case "mailbox": return .yellow
        case "catalyst": return .cyan
        case "sending_approved": return .green
        case "maya": return .green
        default: return .neutral
        }
    }
}

/// Dashboard card offering notifications - instead of a system prompt at
/// launch. Hidden once the person decided either way.
struct NotificationsPromptCard: View {
    @ObservedObject private var push = PushService.shared

    var body: some View {
        if push.authorizationStatus == .notDetermined {
            VStack(alignment: .leading, spacing: 10) {
                Label("Know the moment someone replies", systemImage: "bell.badge")
                    .font(.headline)
                Text("Outreach can notify you about replies, inbox problems, and when Maya starts and finishes her day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Turn on notifications") {
                    Task { await push.requestPermission() }
                }
                .buttonStyle(.pill(.primary, height: 44))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
