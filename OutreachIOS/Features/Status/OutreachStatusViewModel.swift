import Foundation

@MainActor
final class OutreachStatusViewModel: ObservableObject {
    @Published var summary: SignalEngineSummary?
    @Published var isLoading = false
    @Published var errorMessage = ""

    private let apiClient: OutreachAPIClient

    init(apiClient: OutreachAPIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        errorMessage = ""
        do {
            summary = try await apiClient.fetchSignalEngineStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
