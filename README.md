# Outreach iOS

<p align="center">
  <img src="OutreachIOS/Resources/Assets.xcassets/OutreachLogo.imageset/outreach-logo.png" alt="Outreach app icon" width="160">
</p>

Outreach iOS is the native iPhone companion for TODD Outreach. It gives an authenticated Outreach user a quick, read-only view of outreach activity and signal-engine health, while keeping the full editing and operating workspace in the Outreach web app.

The app is intentionally narrow in scope:

- Native sign-in with Apple or Google.
- Biometric re-unlock for Firebase sessions restored on app launch.
- App Store subscription and entitlement gating.
- A status dashboard backed by server-computed signal-engine counts.
- A read-only “Messages Sent” email-activity list.
- One-tap handoff into the signed-in Outreach/TODD web experience.

## Product flow

On launch, `RootView` evaluates the session in this order:

1. Wait for Firebase Auth to resolve the current user.
2. Show `SignInView` when there is no signed-in user.
3. Show `BiometricLockView` when Firebase restored a user but the session has not been unlocked for this process.
4. Refresh the server-side Outreach App Store entitlement.
5. Show `PaywallView` if the user has no active entitlement.
6. Show `OutreachStatusView` for an entitled, unlocked user.

After signing in, `AuthService.bootstrapTenant()` calls the backend bootstrap route so the backend can create or resolve the user’s tenant/contact association. Tenant lookup subsequently mirrors the shared TODD model: `users/{uid}.companyId`, falling back to the Firebase UID when no company ID is present.

## Features

### Status dashboard

`OutreachStatusView` displays the server-computed `SignalEngineSummary`:

- Active threads
- Hot and warm leads
- Drafts ready
- Queued actions
- Messages currently sending
- Stalled/waiting threads
- Threads needing a human decision

The app consumes the backend summary instead of reproducing the web app’s signal-engine calculations locally. Pull to refresh requests a fresh summary.

### Messages Sent

The account menu opens a read-only list of email activity. Each row can show the subject, recipient, date, and whether the message was opened. Pull to refresh reloads the list. Creating, editing, sending, or managing campaigns remains a web-app responsibility.

### Web handoff

The account menu links to Outreach and TODD pages including Home, Growth, Inbox, Outbox, Catalyst, Email Composer, Daily Momentum, Profile, and Help. `TODDAuthKit.WebHandoff` exchanges the current Firebase ID token with the backend and opens the destination already signed in, so the user does not need a second browser login.

### Subscription access

The paywall uses StoreKit 2 through `TODDEntitlementKit`. The app:

- Loads the configured Outreach App Store product.
- Creates and persists a per-user `appAccountToken` UUID.
- Links that token to the backend before starting a purchase.
- Refreshes the server-side entitlement after purchase or restore.
- Uses the backend entitlement as the access decision.

The product ID is currently empty in `project.yml`, so the paywall will report that the subscription is not configured until an App Store product is created and the setting is updated.

## Architecture

The app is SwiftUI-based and uses a small service/view-model layer:

```text
OutreachIOSApp
└── RootView
    ├── SignInView
    ├── BiometricLockView       (TODDAuthKit)
    ├── PaywallView
    └── OutreachStatusView
        └── EmailActivityListView

AuthService         Firebase Auth + Firestore tenant resolution
OutreachAPIClient   Authorized REST calls to todd-backend
EntitlementService  StoreKit 2 + TODDEntitlementKit + backend entitlement
AppConfig           Bundle-backed API/product configuration
```

Important implementation choices:

- API requests use a fresh Firebase ID token in the `Authorization: Bearer <token>` header.
- `TODDAuthKit` supplies the native Apple/Google sign-in controls, session gate, and biometric lock UI.
- `TODDEntitlementKit` supplies purchase and transaction-observer helpers.
- `SignalEngineSummary` and `EmailActivityRecord` decode defensively where the mobile UI only needs a subset of the backend response.
- Release configuration and generated Xcode project files are derived from `project.yml`; do not edit `Generated/Info.plist` or the generated `.xcodeproj` by hand.

## Repository layout

```text
OutreachIOS/
├── App/
│   ├── OutreachIOSApp.swift       App entry point and service composition
│   └── RootView.swift             Authentication, lock, and entitlement routing
├── Features/
│   ├── Auth/                      Sign-in screen
│   ├── EmailActivity/             Read-only sent-message list
│   ├── Paywall/                   StoreKit subscription UI
│   └── Status/                    Signal-engine dashboard and view model
├── Models/                        API response/request models
├── Resources/                     App icon and Outreach logo assets
└── Services/
    ├── AppConfig.swift            Bundle configuration reader
    ├── AuthService.swift          Firebase auth and tenant bootstrap
    ├── EntitlementService.swift   StoreKit entitlement lifecycle
    └── OutreachAPIClient.swift    Authenticated REST client

OutreachIOS.entitlements           Sign in with Apple capability
project.yml                        XcodeGen source of truth
Generated/                          XcodeGen output; ignored by Git
```

## Requirements

- macOS with Xcode 27 or later.
- iOS 17.0 or later.
- XcodeGen 2.38 or later.
- Access to the sibling local packages:
  - `../TODDAuthKit`
  - `../TODDEntitlementKit`
- A Firebase project configured for the app’s bundle identifier.
- Apple Developer access for Sign in with Apple and App Store configuration.

The bundle identifier is `tech.taliferro.outreachios` and the deployment target is iOS 17.0.

## First-time setup

### 1. Provide Firebase configuration

Create or obtain an iOS app registration in the TODD Firebase project for bundle ID `tech.taliferro.outreachios`. Download its `GoogleService-Info.plist` and add it to the `OutreachIOS` target, preferably at:

```text
OutreachIOS/GoogleService-Info.plist
```

The file is intentionally ignored by Git. It is required by `FirebaseApp.configure()` for Firebase Auth and Firestore, and must be included in the application target’s resources.

The Google Sign-In reversed client ID is currently declared in `project.yml` as the callback URL scheme. If Firebase provides a different reversed client ID for the app registration, update the `CFBundleURLTypes` entry in `project.yml` before regenerating the project.

### 2. Enable Apple capabilities

In the Apple Developer portal, enable Sign in with Apple for the App ID matching `tech.taliferro.outreachios`. The local entitlement is already declared in `OutreachIOS.entitlements`, but the portal-side capability is required for real authentication.

### 3. Configure the App Store product

Create the Outreach subscription product in App Store Connect and set `OUTREACH_APP_STORE_PRODUCT_ID` in `project.yml` to its exact product ID. The value is copied into `Generated/Info.plist` and read by `AppConfig` at runtime.

The backend must also support the `outreach` product key and the corresponding App Store server-side entitlement records. Until both the product and backend configuration exist, a successful build will still stop at the paywall.

### 4. Generate the Xcode project

From this directory:

```bash
brew install xcodegen  # if XcodeGen is not installed
xcodegen generate
open OutreachIOS.xcodeproj
```

Select an iOS Simulator or a signed physical device and run the `OutreachIOS` scheme. Add `GoogleService-Info.plist` to the target if XcodeGen does not pick up the local file automatically.

## Configuration

Configuration is defined in `project.yml` and exposed to the app through generated Info.plist keys:

| Key | Current value | Purpose |
| --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` | `tech.taliferro.outreachios` | iOS application identifier |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.0` | Minimum supported iOS version |
| `OUTREACH_API_BASE_URL` | `https://api.taliferro.tech/api` | Backend API root |
| `OUTREACH_APP_STORE_PRODUCT_ID` | empty | StoreKit subscription product ID |

Change `project.yml`, then run `xcodegen generate` again. Do not edit `Generated/Info.plist` directly.

## Backend API contract

All routes below are relative to `OUTREACH_API_BASE_URL` and receive a Firebase ID token in the `Authorization` header.

| Method | Route | Used by | Expected result |
| --- | --- | --- | --- |
| `POST` | `/mobile/auth/bootstrap` | `AuthService` | Resolves/creates the tenant and returns `tenantId` |
| `GET` | `/mobile/outreach/status` | `OutreachAPIClient` | Returns `data.summary` matching `SignalEngineSummary` |
| `GET` | `/mobile/outreach/emails` | `EmailActivityListViewModel` | Returns `data.records` matching `EmailActivityRecord` |
| `POST` | `/app-store/link` | `EntitlementService` | Links the user’s App Store account token to product key `outreach` |
| `GET` | `/app-store/entitlement/outreach` | `EntitlementService` | Returns the server-side active entitlement and records |

The mobile client expects successful JSON responses and treats non-2xx responses as errors. Backend route implementations live in the shared `todd-backend` repository; this app does not duplicate the server’s business logic.

## Development notes

- Debug launches call `Auth.auth().signOut()` in `OutreachIOSApp`, so local runs begin signed out. Remove or adjust that behavior only if you intentionally want to test session restoration.
- A restored Firebase session is not trusted until the shared biometric session gate is unlocked.
- Sign-in buttons are Apple and Google. Phone authentication is not currently included.
- `GoogleService-Info.plist`, signing configuration, provisioning profiles, archives, and other local credentials must not be committed.
- `Generated/` and `OutreachIOS.xcodeproj/` are ignored outputs. Regenerate them from `project.yml` when configuration changes.
- There are currently no test targets configured in `project.yml`; `xcodebuild test` will not have an app test target until one is added.

## Verification checklist

Before handing off a build, verify:

1. `xcodegen generate` completes successfully.
2. `GoogleService-Info.plist` belongs to bundle ID `tech.taliferro.outreachios` and is included in the app target.
3. Sign in with Apple and Google callbacks return to the app.
4. A newly signed-in user completes `/mobile/auth/bootstrap`.
5. A restored session requires biometric unlock.
6. The status dashboard loads and pull-to-refresh works.
7. The Messages Sent sheet loads and handles an empty result.
8. The configured StoreKit product loads, purchase/restore flows return, and the backend entitlement unlocks the dashboard.
9. Account-menu web handoff opens the selected page already authenticated.

## Related projects

- [`../TODDAuthKit`](../TODDAuthKit) — shared native authentication, biometric session gate, and web handoff.
- [`../TODDEntitlementKit`](../TODDEntitlementKit) — shared StoreKit 2 purchase helpers and transaction observation.
- `todd-backend` — shared API, authentication, tenant, Outreach, and App Store entitlement services.
