import SwiftUI

/// Everything Outreach and Maya told you about, newest first - including
/// what was held for quiet hours or switched off, so nothing is missed.
struct ActivityView: View {
    let apiClient: OutreachAPIClient
    let onOpen: (URL) -> Void
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
                List(items) { item in
                    Button {
                        if let route = item.route, let url = URL(string: route), !route.isEmpty { onOpen(url) }
                    } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ item: ActivityItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .foregroundStyle(OutreachTheme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold))
                if let body = item.body, !body.isEmpty {
                    Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
                if let date = item.date {
                    Text(date, style: .relative).font(.caption).foregroundStyle(.tertiary)
                        + Text(" ago").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func load() async {
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
                Button("Turn On Notifications") {
                    Task { await push.requestPermission() }
                }
                .buttonStyle(.borderedProminent)
                .tint(OutreachTheme.accent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
