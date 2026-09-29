import SwiftUI
import AuthenticationServices

/// Connect an inbox inside the app. Gmail / Google Workspace goes through
/// Google's own approval page (ASWebAuthenticationSession, returning to
/// `tech.taliferro.outreachios://mailbox-connected`) - no password.
/// Other providers take an app password, typed here on a signed-in screen
/// and sent straight to the backend, which stores it encrypted; it's never
/// kept on the device.
struct ConnectMailboxView: View {
    let apiClient: OutreachAPIClient
    let onConnected: () -> Void

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var email: String
    @State private var provider: MailProvider
    @State private var appPassword = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var isWorking = false
    @State private var status: String?
    @State private var errorMessage: String?

    init(apiClient: OutreachAPIClient, email: String, provider: MailProvider, onConnected: @escaping () -> Void) {
        self.apiClient = apiClient
        self.onConnected = onConnected
        _email = State(initialValue: email)
        _provider = State(initialValue: provider)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect an inbox")
                    .font(.largeTitle.bold())
                Text("Outreach reads replies so it knows who answered, and only sends what you approve.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Who hosts it?").font(.headline)
                    FlowChips(items: MailProvider.allCases, selected: provider, label: { $0.label }) { provider = $0 }
                }

                if provider == .gmail {
                    googleSection
                } else {
                    passwordSection
                }

                if let status {
                    Label(status, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Gmail

    private var googleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !email.isEmpty {
                Text(email).font(.title3.bold())
            }
            Text("Signing in with Google told TODD who you are. Letting Outreach see replies and send from your Gmail is a separate permission Google asks you to approve once. TODD never sees your Google password, and you can remove access any time in your Google account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            primaryButton(isWorking ? "Opening Google..." : "Connect with Google") {
                Task { await connectGoogle() }
            }
        }
    }

    private func connectGoogle() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let url = try await apiClient.startGoogleMailboxConnection()
            let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: "tech.taliferro.outreachios")
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if items.first(where: { $0.name == "status" })?.value == "success" {
                status = "Connected. Outreach is syncing your inbox."
                onConnected()
            } else {
                errorMessage = items.first(where: { $0.name == "message" })?.value ?? "Google didn't finish connecting. Please try again."
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closed Google's page - nothing to report.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - App password

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Email address") {
                TextField("you@company.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            field("App password") {
                SecureField("App password", text: $appPassword)
                    .textContentType(.password)
            }
            if let help = provider.appPasswordHelpURL {
                Link("How to create an app password for \(provider.label)", destination: help)
                    .font(.footnote)
            }
            Text("An app password isn't your regular password, and you can revoke it any time. TODD stores it encrypted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if provider == .otherImap {
                Text("Mail server").font(.headline).padding(.top, 4)
                field("Incoming (IMAP) server") { TextField("imap.example.com", text: $imapHost).textInputAutocapitalization(.never).autocorrectionDisabled() }
                field("IMAP port") { TextField("993", text: $imapPort).keyboardType(.numberPad) }
                field("Outgoing (SMTP) server") { TextField("smtp.example.com", text: $smtpHost).textInputAutocapitalization(.never).autocorrectionDisabled() }
                field("SMTP port") { TextField("465", text: $smtpPort).keyboardType(.numberPad) }
            }

            HStack(spacing: 10) {
                secondaryButton("Test") { Task { await test() } }
                primaryButton(isWorking ? "Saving..." : "Connect") { Task { await save() } }
            }
            .disabled(isWorking || !canSubmit)
        }
    }

    private var canSubmit: Bool {
        let parts = email.split(separator: "@")
        let validEmail = parts.count == 2 && parts[1].contains(".")
        let serversOK = provider != .otherImap || (!imapHost.isEmpty && !smtpHost.isEmpty)
        return validEmail && !appPassword.isEmpty && serversOK
    }

    private var request: MailboxConnectRequest {
        MailboxConnectRequest(
            emailAddress: email.trimmingCharacters(in: .whitespaces).lowercased(),
            provider: provider.rawValue,
            secret: appPassword,
            displayName: nil,
            imap: provider == .otherImap ? MailboxServerSettings(host: imapHost, port: Int(imapPort) ?? 993, secure: true) : nil,
            smtp: provider == .otherImap ? MailboxServerSettings(host: smtpHost, port: Int(smtpPort) ?? 465, secure: (Int(smtpPort) ?? 465) == 465) : nil
        )
    }

    private func test() async {
        isWorking = true
        errorMessage = nil
        status = nil
        defer { isWorking = false }
        do {
            try await apiClient.testMailbox(request)
            status = "It works - tap Connect to save it."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await apiClient.saveMailbox(request)
            appPassword = ""
            status = "Connected. Outreach is syncing your inbox."
            onConnected()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pieces

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.15)))
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(OutreachTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
        }
        .disabled(isWorking)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(OutreachTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(OutreachTheme.accent)
        }
    }
}

extension MailProvider {
    /// Each provider's own instructions for creating an app password.
    var appPasswordHelpURL: URL? {
        switch self {
        case .gmail: return URL(string: "https://support.google.com/accounts/answer/185833")
        case .outlook: return URL(string: "https://support.microsoft.com/account-billing/5896ed9b-4263-e681-128a-a6f2979a7944")
        case .icloud: return URL(string: "https://support.apple.com/102654")
        case .yahoo: return URL(string: "https://help.yahoo.com/kb/SLN15241.html")
        case .otherImap: return nil
        }
    }
}

/// Provider chips that wrap - one tap, a sensible default already picked.
private struct FlowChips<Item: Hashable>: View {
    let items: [Item]
    let selected: Item
    let label: (Item) -> String
    let onSelect: (Item) -> Void

    var body: some View {
        ChipWrapLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selected
                Button { onSelect(item) } label: {
                    HStack(spacing: 6) {
                        if isSelected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        Text(label(item)).font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(isSelected ? OutreachTheme.accent : Color(.secondarySystemGroupedBackground)))
                    .overlay(Capsule().strokeBorder(isSelected ? OutreachTheme.accent : Color.primary.opacity(0.2)))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ChipWrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
