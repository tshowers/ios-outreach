import SwiftUI
import FirebaseAuth
import FirebaseCore
import TODDAuthKit
import TODDAwardsKit

@main
struct OutreachIOSApp: App {
    @StateObject private var authService: AuthService
    @StateObject private var entitlementService: EntitlementService
    @StateObject private var awardsService: AwardsService
    private let apiClient: OutreachAPIClient

    init() {
        FirebaseApp.configure()

        #if DEBUG
        try? Auth.auth().signOut()
        #endif

        let config = AppConfig.fromBundle()
        let authService = AuthService()
        _authService = StateObject(wrappedValue: authService)
        _awardsService = StateObject(wrappedValue: OutreachAwards.makeService(authService: authService))
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
            if PaywallScreenshot.current != nil {
                PaywallView(entitlementService: entitlementService, onSignOut: {})
            } else {
                RootView(authService: authService, entitlementService: entitlementService, apiClient: apiClient, awardsService: awardsService)
                    .onOpenURL { url in
                        _ = GoogleSignInHelper.handle(url)
                    }
            }
        }
    }
}
