import Foundation

/// Mirrors `buildSignalEngineSummary()` in
/// `todd-backend/functions/outreach/momentum/momentum.controller.js` -
/// server-computed aggregate counts across every live outreach thread, the
/// same numbers `outreach-home.component.ts` derives client-side from the
/// full thread list. Using the server-computed summary directly rather than
/// re-deriving from raw threads keeps this native status view from having
/// to duplicate that derivation logic.
struct SignalEngineSummary: Codable {
    let activeThreads: Int
    let queuedActions: Int
    let sending: Int
    let hotLeads: Int
    let warmLeads: Int
    let draftReady: Int
    let stalledWaiting: Int
    let needsHuman: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeThreads = try container.decodeIfPresent(Int.self, forKey: .activeThreads) ?? 0
        queuedActions = try container.decodeIfPresent(Int.self, forKey: .queuedActions) ?? 0
        sending = try container.decodeIfPresent(Int.self, forKey: .sending) ?? 0
        hotLeads = try container.decodeIfPresent(Int.self, forKey: .hotLeads) ?? 0
        warmLeads = try container.decodeIfPresent(Int.self, forKey: .warmLeads) ?? 0
        draftReady = try container.decodeIfPresent(Int.self, forKey: .draftReady) ?? 0
        stalledWaiting = try container.decodeIfPresent(Int.self, forKey: .stalledWaiting) ?? 0
        needsHuman = try container.decodeIfPresent(Int.self, forKey: .needsHuman) ?? 0
    }
}

struct SignalEngineBootstrapData: Codable {
    let summary: SignalEngineSummary
}

struct SignalEngineBootstrapEnvelope: Codable {
    let success: Bool
    let data: SignalEngineBootstrapData
}
