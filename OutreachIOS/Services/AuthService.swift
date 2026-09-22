import Foundation
import FirebaseAuth
import FirebaseFirestore
import TODDAuthKit

/// Mirrors `frontend/src/app/services/auth.service.ts`'s `resolveAssignedTenantId`
/// - Outreach's email activity is shared, tenant-scoped team data, so this
/// follows network-ios's/maya-ios's AuthService rather than pulse-ios's
/// simpler uid-only version.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading = true
    @Published private(set) var tenantId: String?

    let sessionGate = SessionUnlockGate()
    private var handle: AuthStateDidChangeListenerHandle?
    private let firestore = Firestore.firestore()

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.currentUser = user
            self.isLoading = false
            self.sessionGate.handleAuthStateChange(hasUser: user != nil)
            Task { await self.refreshTenantId() }
        }
    }

    deinit {
        if let handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var userId: String? { currentUser?.uid }
    var userEmail: String? { currentUser?.email }

    func signOut() throws {
        try Auth.auth().signOut()
        tenantId = nil
    }

    func freshIdToken() async throws -> String {
        guard let user = currentUser else {
            throw AuthServiceError.notSignedIn
        }
        return try await user.getIDToken()
    }

    /// Calls the backend's get-or-create tenant/contact endpoint
    /// (`POST /api/mobile/auth/bootstrap`, `mobileAuthRoutes.js`) right after a
    /// fresh native sign-in. Updates `tenantId` with the authoritative result.
    func bootstrapTenant() async throws {
        let idToken = try await freshIdToken()
        let url = AppConfig.fromBundle().apiBaseURL.appending(path: "mobile/auth/bootstrap")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw AuthServiceError.bootstrapFailed
        }

        let decoded = try JSONDecoder().decode(BootstrapResponse.self, from: data)
        tenantId = decoded.tenantId
    }

    private func refreshTenantId() async {
        guard let uid = currentUser?.uid else {
            tenantId = nil
            return
        }

        do {
            let snapshot = try await firestore.collection("users").document(uid).getDocument()
            let companyId = (snapshot.data()?["companyId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            tenantId = (companyId?.isEmpty == false ? companyId : nil) ?? uid
        } catch {
            tenantId = uid
        }
    }
}

enum AuthServiceError: LocalizedError {
    case notSignedIn
    case bootstrapFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to load your email activity."
        case .bootstrapFailed:
            return "Unable to set up your account. Please try again."
        }
    }
}

private struct BootstrapResponse: Decodable {
    let success: Bool
    let tenantId: String
    let isNewTenant: Bool
}
