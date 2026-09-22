import SwiftUI
import FirebaseAuth
import FirebaseCore
import TODDAuthKit

@main
struct OutreachIOSApp: App {
    @StateObject private var authService: AuthService
    @StateObject private var entitlementService: EntitlementService
    private let apiClient: OutreachAPIClient

    init() {
        FirebaseApp.configure()

        #if DEBUG
        try? Auth.auth().signOut()
        #endif

        let config = AppConfig.fromBundle()
        let authService = AuthService()
        _authService = StateObject(wrappedValue: authService)
        let apiClient = OutreachAPIClient(config: config, authService: authService)
        self.apiClient = apiClient
        _entitlementService = StateObject(wrappedValue: EntitlementService(
            apiClient: apiClient,
            authService: authService,
            config: config
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService, entitlementService: entitlementService, apiClient: apiClient)
                .onOpenURL { url in
                    _ = GoogleSignInHelper.handle(url)
                }
        }
    }
}
