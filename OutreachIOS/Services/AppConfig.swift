import Foundation

struct AppConfig {
    let apiBaseURL: URL
    let outreachProductId: String

    static func fromBundle(bundle: Bundle = .main) -> AppConfig {
        let baseURLString = bundle.object(forInfoDictionaryKey: "OUTREACH_API_BASE_URL") as? String ?? ""
        let outreachProductId = bundle.object(forInfoDictionaryKey: "OUTREACH_APP_STORE_PRODUCT_ID") as? String ?? ""

        guard let apiBaseURL = URL(string: baseURLString) else {
            fatalError("Missing OUTREACH_API_BASE_URL in app configuration.")
        }

        return AppConfig(apiBaseURL: apiBaseURL, outreachProductId: outreachProductId)
    }
}
