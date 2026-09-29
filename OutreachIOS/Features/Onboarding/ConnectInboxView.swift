import SwiftUI

/// Shown right after sign-in when the wizard picked an inbox: one tap opens
/// the in-app Connect page pre-filled with the address - Gmail connects
/// through Google's approval page, other providers take an app password on
/// that signed-in page. The password is never typed into the pre-sign-in
/// wizard or stored on the device.
/// "Not now" keeps the draft for next launch.
struct ConnectInboxView: View {
    let onConnect: (_ draft: InboxDraft) -> Void
    let onFinished: () -> Void
    @State private var draft = InboxDraft.load()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect your inbox")
                        .font(.largeTitle.bold())
                    Text("Last step. Outreach needs to see replies to tell you who to follow up with.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(draft.provider.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.5)
                            .foregroundStyle(OutreachTheme.accent)
                        Text(draft.trimmedEmail)
                            .font(.title3.bold())
                        Label(draft.provider.howItConnects, systemImage: "lock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(.separator), lineWidth: 1))

                    Button {
                        let picked = draft
                        InboxDraft.clear()
                        onFinished()
                        onConnect(picked)
                    } label: {
                        Text(draft.provider == .gmail ? "Connect with Google" : "Connect \(draft.provider.label)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OutreachTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    Text(draft.provider == .gmail ? "Google asks you to approve access once - that's separate from signing in." : "You'll paste an app password on the next screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { onFinished() }
                }
            }
        }
    }
}
