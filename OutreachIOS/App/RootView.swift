import SwiftUI
import TODDAuthKit

struct RootView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    let apiClient: OutreachAPIClient

    var body: some View {
        Group {
            if authService.isLoading {
                ProgressView()
            } else if authService.currentUser == nil {
                SignInView(authService: authService)
            } else if !authService.sessionGate.isUnlocked {
                BiometricLockView(reason: "Unlock Outreach to view your email activity.") {
                    authService.sessionGate.markUnlocked()
                }
            } else if entitlementService.isLoadingEntitlement {
                ProgressView()
                    .task { await entitlementService.refreshEntitlement() }
            } else if !entitlementService.isEntitled {
                PaywallView(entitlementService: entitlementService, onSignOut: signOut)
            } else {
                OutreachStatusView(apiClient: apiClient, authService: authService)
            }
        }
    }

    private func signOut() {
        try? authService.signOut()
    }
}
