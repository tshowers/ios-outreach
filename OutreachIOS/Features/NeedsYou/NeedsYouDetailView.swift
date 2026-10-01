import SwiftUI

/// One person waiting on you: what they said, why Maya stopped, and the
/// quick actions - send Maya's reply, write your own, call / text / email,
/// or mark it done.
struct NeedsYouDetailView: View {
    let item: NeedsYouItem
    @ObservedObject var store: NeedsYouStore
    @Binding var path: [OutreachRoute]
    @Environment(\.openURL) private var openURL
    @State private var isMarkingDone = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !item.replyText.isEmpty || !item.replySummary.isEmpty {
                    card(title: "What they said") {
                        if !item.replyText.isEmpty {
                            Text(item.replyText).font(.body).textSelection(.enabled)
                        }
                        if !item.replySummary.isEmpty {
                            Label(item.replySummary, systemImage: "sparkles")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                card(title: item.reasonLabel) {
                    if !item.reasonDetail.isEmpty {
                        Text(item.reasonDetail).font(.subheadline)
                    }
                    if !item.nextMove.isEmpty {
                        Text("Next: \(item.nextMove)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                actions

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(item.contactName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.contactName).font(.title2.weight(.bold))
            if !item.companyName.isEmpty {
                Text(item.companyName).foregroundStyle(.secondary)
            }
            if !item.lastSubject.isEmpty {
                Text(item.lastSubject).font(.subheadline).foregroundStyle(.secondary)
            }
            if let date = item.repliedDate {
                Text("Replied \(date, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if item.hasMayaDraft {
                Button {
                    path.append(.needsYouReply(item, useMayaDraft: true))
                } label: {
                    Label("Review Maya's Reply", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(OutreachTheme.accent)
            }

            Button {
                path.append(.needsYouReply(item, useMayaDraft: false))
            } label: {
                Label("Write a Reply", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(item.hasMayaDraft ? .primary : OutreachTheme.accent)

            HStack(spacing: 12) {
                contactButton("Call", systemImage: "phone", url: telURL("tel"))
                contactButton("Text", systemImage: "message", url: telURL("sms"))
                contactButton("Email", systemImage: "envelope", url: item.email.isEmpty ? nil : URL(string: "mailto:\(item.email)"))
            }

            Button {
                Task { await markDone() }
            } label: {
                Label(isMarkingDone ? "Marking Done…" : "Done - I've Handled It", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
            .disabled(isMarkingDone)
        }
        .controlSize(.large)
    }

    private func telURL(_ scheme: String) -> URL? {
        let digits = item.phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "\(scheme):\(digits)")
    }

    private func contactButton(_ title: String, systemImage: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(url == nil)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func markDone() async {
        isMarkingDone = true
        do {
            try await store.markDone(item)
            if path.last == .needsYouDetail(item) { path.removeLast() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isMarkingDone = false
    }
}
