import SwiftUI
import TODDAuthKit

/// Native sign-in (Apple + Google), replacing the web-redirect HostedLogin
/// flow removed 2026-09-20 - see network-ios's SignInView for the full
/// reasoning and docs/app-store-exclusive-billing-plan.md's "Native
/// sign-in" section. Phone auth is deliberately not included yet.
struct SignInView: View {
    @ObservedObject var authService: AuthService
    @State private var errorMessage = ""
    @State private var isBootstrapping = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("OutreachLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("Outreach")
                .font(.largeTitle.bold())
            Text("Sign in with your TODD account to see your email activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                SignInWithAppleButtonView(
                    onSignedIn: { Task { await bootstrap() } },
                    onError: { handle($0) }
                )
                SignInWithGoogleButtonView(
                    onSignedIn: { Task { await bootstrap() } },
                    onError: { handle($0) }
                )
            }
            .padding(.horizontal, 32)
            .disabled(isBootstrapping)

            if isBootstrapping {
                ProgressView()
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    @MainActor
    private func bootstrap() async {
        errorMessage = ""
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            try await authService.bootstrapTenant()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handle(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
