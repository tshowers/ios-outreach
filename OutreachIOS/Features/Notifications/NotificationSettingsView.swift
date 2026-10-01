import SwiftUI
import UIKit

/// Account -> Notifications: turn notifications on, and one switch per kind.
/// Replies and inbox problems arrive at any hour; the rest wait out quiet
/// hours (9pm-6am).
struct NotificationSettingsView: View {
    let apiClient: OutreachAPIClient
    @ObservedObject private var push = PushService.shared
    @State private var preferences = PushPreferences()
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                switch push.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    Label("Notifications are on", systemImage: "bell.badge.fill")
                        .foregroundStyle(.green)
                case .denied:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifications are off for Outreach", systemImage: "bell.slash")
                        Text("Turn them on in Settings to hear about replies right away.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Get a notification when someone replies, when your inbox needs attention, and when Maya starts and finishes her day.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Turn On Notifications") {
                            Task { await push.requestPermission() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section {
                toggle("Replies", detail: "When someone writes back.", isOn: $preferences.replies)
                toggle("Inbox problems", detail: "When Outreach can't reach your inbox.", isOn: $preferences.mailbox)
            } header: {
                Text("Any time")
            } footer: {
                Text("These come through even during quiet hours.")
            }

            Section {
                toggle("Maya's day", detail: "When she starts, and her summary when she's done.", isOn: $preferences.maya)
                toggle("Catalyst batches", detail: "When a bulk send finishes.", isOn: $preferences.catalyst)
                toggle("Sending approved", detail: "When you're cleared to send from Outreach.", isOn: $preferences.sendingApproved)
            } header: {
                Text("Daytime")
            } footer: {
                Text("Held from 9pm to 6am and delivered in the morning.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .disabled(isLoading)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await push.refreshStatus()
            await load()
        }
        .onChange(of: preferences) { oldValue, newValue in
            guard !isLoading, oldValue != newValue else { return }
            Task { await save(newValue, previous: oldValue) }
        }
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        isLoading = true
        do {
            preferences = try await apiClient.fetchPushPreferences()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ updated: PushPreferences, previous: PushPreferences) async {
        do {
            let saved = try await apiClient.savePushPreferences(updated)
            errorMessage = nil
            if saved != preferences {
                isLoading = true
                preferences = saved
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = true
            preferences = previous
            isLoading = false
        }
    }
}
