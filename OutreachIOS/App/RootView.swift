import SwiftUI
import TODDAuthKit
import TODDAwardsKit

struct RootView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var entitlementService: EntitlementService
    @ObservedObject var awardsService: AwardsService
    /// Observed directly (as pulse-ios/network-ios do): `sessionGate` is its
    /// own ObservableObject, so observing only `authService` never redraws
    /// this view when Face ID succeeds - the lock screen stayed up after
    /// the green checkmark.
    @ObservedObject private var sessionGate: SessionUnlockGate
    let apiClient: OutreachAPIClient

    init(authService: AuthService, entitlementService: EntitlementService, apiClient: OutreachAPIClient, awardsService: AwardsService) {
        self.authService = authService
        self.entitlementService = entitlementService
        self.awardsService = awardsService
        self.sessionGate = authService.sessionGate
        self.apiClient = apiClient
    }

    var body: some View {
        Group {
            if authService.isLoading {
                ProgressView()
            } else if authService.currentUser == nil {
                // Pre-sign-in wizard (inbox, name)
                // ending in sign-in; returning users skip to SignInView
                // from inside it.
                OnboardingWizardView(authService: authService, awardsService: awardsService)
            } else if !sessionGate.isUnlocked {
                BiometricLockView(reason: "Unlock Outreach to view your email activity.") {
                    sessionGate.markUnlocked()
                }
            } else if entitlementService.isLoadingEntitlement {
                ProgressView()
                    .task { await entitlementService.refreshEntitlement() }
            } else if !entitlementService.isEntitled {
                PaywallView(entitlementService: entitlementService, onSignOut: signOut)
            } else {
                OutreachStatusView(apiClient: apiClient, authService: authService, awardsService: awardsService)
            }
        }
        .onChange(of: authService.userId) { oldValue, newValue in
            // Pull this account's awards first (and push any earned while
            // signed out), then record sign-up - so an award already
            // earned on another device isn't celebrated again.
            if oldValue == nil, newValue != nil {
                Task {
                    await awardsService.sync()
                    awardsService.recordSignedUp()
                }
            }
        }
        .task {
            if authService.userId != nil { await awardsService.sync() }
        }
        .fullScreenCover(item: Binding(
            get: { awardsService.pendingUnlock },
            set: { newValue in if newValue == nil { awardsService.dismissCurrentUnlock() } }
        )) { award in
            AwardUnlockView(
                award: award,
                appName: "Outreach",
                unlockedCount: awardsService.unlockedCount,
                totalCount: awardsService.totalCount,
                onContinue: { awardsService.dismissCurrentUnlock() }
            )
        }
    }

    private func signOut() {
        Task {
            await PushService.shared.unregister()
            try? authService.signOut()
        }
    }
}
