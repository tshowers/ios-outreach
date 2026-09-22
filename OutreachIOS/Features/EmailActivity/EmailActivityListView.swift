import SwiftUI

/// Read-only email activity glance - "Messages Sent" in OutreachStatusView's
/// account menu, presented as a sheet (matching network-ios's
/// NetworkStatusView pattern - sign-out lives on the status screen this is
/// reached from, not here).
struct EmailActivityListView: View {
    @StateObject private var viewModel: EmailActivityListViewModel
    @Environment(\.dismiss) private var dismiss

    init(apiClient: OutreachAPIClient) {
        _viewModel = StateObject(wrappedValue: EmailActivityListViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.records.isEmpty {
                    ProgressView()
                } else if viewModel.records.isEmpty {
                    ContentUnavailableView("No email activity yet", systemImage: "paperplane", description: Text("Sent emails will show up here."))
                } else {
                    List(viewModel.records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(record.subject?.isEmpty == false ? record.subject! : "(no subject)")
                                    .font(.headline)
                                Spacer()
                                if record.opened == true {
                                    Image(systemName: "envelope.open.fill")
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("Opened")
                                }
                            }
                            if let to = record.to, !to.isEmpty {
                                Text("To: \(to)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let date = record.date, !date.isEmpty {
                                Text(date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Messages Sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
