import Foundation

@MainActor
final class EmailActivityListViewModel: ObservableObject {
    @Published private(set) var records: [EmailActivityRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: OutreachAPIClient

    init(apiClient: OutreachAPIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            records = try await apiClient.fetchEmailActivity()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
