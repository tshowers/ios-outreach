import SwiftUI

/// Catalyst's stale-contact queue - the people you haven't reached in the
/// longest time, stalest first (same rules as web Catalyst). Tap one to have
/// TODD draft a tailored email you can edit and send.
struct CatalystView: View {
    let apiClient: OutreachAPIClient
    @Binding var path: [OutreachRoute]
    /// Contacts emailed from here this session - dropped from the list.
    @Binding var sentContactIds: Set<String>

    @State private var queue: [CatalystContact] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var visible: [CatalystContact] {
        queue.filter { !sentContactIds.contains($0.id) }
    }

    var body: some View {
        Group {
            if isLoading && queue.isEmpty {
                ProgressView()
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label(errorMessage == nil ? "Nobody's waiting" : "Couldn't load Catalyst", systemImage: "bolt.badge.clock")
                } description: {
                    Text(errorMessage ?? "Catalyst lists contacts with a first name, a company and an email address, longest-quiet first. Add some in Network and they'll show up here.")
                }
            } else {
                List {
                    Section {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Section("Stalest first") {
                        ForEach(visible) { contact in
                            NavigationLink(value: OutreachRoute.catalystCompose(contact)) {
                                CatalystRow(contact: contact)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Catalyst")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var summary: String {
        let urgent = visible.filter { $0.daysSinceLastContact >= 30 }.count
        let oldest = visible.first?.daysSinceLastContact ?? 0
        if urgent == 0 { return "Everyone here heard from you in the last month. Nice." }
        return "\(urgent) \(urgent == 1 ? "person hasn't" : "people haven't") heard from you in 30+ days. The longest: \(oldest) days."
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            queue = try await apiClient.fetchCatalystQueue()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CatalystRow: View {
    let contact: CatalystContact

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName).font(.subheadline.weight(.semibold))
                if let company = contact.companyName, !company.isEmpty {
                    Text([contact.profession, company].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(contact.staleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(.vertical, 2)
    }

    /// Red after two months, orange after one, otherwise the brand green.
    private var color: Color {
        switch contact.daysSinceLastContact {
        case 60...: return .red
        case 30...: return .orange
        default: return OutreachTheme.accent
        }
    }
}
