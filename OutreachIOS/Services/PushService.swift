import Foundation
import UIKit
import UserNotifications

/// Push notifications (Outreach 1.1): asking permission, registering this
/// device with todd-backend (`/mobile/push/devices`, pushRoutes.js), and
/// handing a tapped notification's route to the dashboard.
///
/// Permission is never asked at launch - the dashboard shows a card, and
/// Account -> Notifications has the switch - so the system prompt only
/// appears after the person chose to turn notifications on.
@MainActor
final class PushService: ObservableObject {
    static let shared = PushService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Set when a notification is tapped, e.g. "outreach://needs-you/<id>";
    /// the dashboard opens it and clears it.
    @Published var pendingRoute: URL?

    private var apiClient: OutreachAPIClient?
    private var registeredToken: String?

    #if DEBUG
    private let environment = "sandbox"
    #else
    // TestFlight and App Store builds use Apple's production push service.
    private let environment = "production"
    #endif

    func configure(apiClient: OutreachAPIClient) {
        self.apiClient = apiClient
    }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows the system prompt (first time only) and registers the device.
    /// - Returns: whether notifications are now allowed.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// On launch and after sign-in: re-register when already allowed, so the
    /// backend always has this device's current token.
    func registerIfAllowed() async {
        await refreshStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// From AppDelegate when Apple hands over the device token.
    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        registeredToken = token
        Task { await sendTokenToBackend(token) }
    }

    private func sendTokenToBackend(_ token: String) async {
        guard let apiClient else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        do {
            try await apiClient.registerPushDevice(token: token, environment: environment, appVersion: version)
        } catch {
            // Not signed in yet, or offline: registerIfAllowed() runs again
            // after sign-in and on the next launch.
        }
    }

    /// Before signing out, so this phone stops getting the account's pushes.
    func unregister() async {
        guard let apiClient, let token = registeredToken else { return }
        try? await apiClient.unregisterPushDevice(token: token)
        registeredToken = nil
    }
}
