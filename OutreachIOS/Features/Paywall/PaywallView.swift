import SwiftUI
import StoreKit
import TODDEntitlementKit

/// Shown after sign-in + biometric unlock when the signed-in tenant has no
/// active App Store entitlement for Outreach.
struct PaywallView: View {
    @ObservedObject var entitlementService: EntitlementService
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Subscribe to Outreach")
                .font(.title2.bold())
            Text("An active subscription is required to see your email activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let preview = PaywallScreenshot.current {
                Button {} label: {
                    HStack {
                        Text(preview.name)
                        Spacer()
                        Text("\(preview.price) / month")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.top, 16)
                Text("Renews monthly until canceled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if entitlementService.isLoadingProducts {
                ProgressView()
                    .padding(.top, 24)
            } else if entitlementService.products.isEmpty {
                Button("Try Again") {
                    Task { await entitlementService.loadProducts() }
                }
                .buttonStyle(.bordered)
                .padding(.top, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(entitlementService.products) { product in
                        Button {
                            Task { await entitlementService.purchase(product) }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer()
                                Text(product.displayPriceWithPeriod)
                                    .foregroundStyle(.secondary)
                                if let renewal = product.renewalText {
                                    Text("\(renewal) until canceled.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(entitlementService.isPurchasing)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
            }

            Button("Restore Purchases") {
                Task { await entitlementService.restorePurchases() }
            }
            .font(.footnote)
            .disabled(entitlementService.isPurchasing)
            .padding(.top, 4)

            if let errorMessage = entitlementService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            SubscriptionLegalFooter()
                .padding(.top, 8)

            Spacer()

            Button("Sign out", role: .destructive, action: onSignOut)
                .font(.footnote)
                .padding(.bottom, 8)
        }
        .padding()
        .task {
            await entitlementService.loadProducts()
        }
    }
}
