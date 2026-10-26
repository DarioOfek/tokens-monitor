import Foundation

enum Provider: String, CaseIterable, Identifiable {
    case anthropic, openAI, xAI

    var id: String { rawValue }
    var name: String {
        switch self {
        case .anthropic: "Claude"
        case .openAI: "Codex"
        case .xAI: "Grok Bot"
        }
    }
    var vendor: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .xAI: "xAI"
        }
    }
    var accountURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://claude.ai/settings/usage")
        case .openAI: nil
        case .xAI: URL(string: "https://grok.com/dashboard/billing")
        }
    }
}

struct UsageLimit: Identifiable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetAt: Date?
    let resetDescription: String?

    var clampedUsedPercent: Double { min(100, max(0, usedPercent)) }
}

enum SourceState {
    case needsConnection
    case loading
    case fresh
    case stale(String)
}

struct ProviderUsage {
    let provider: Provider
    var limits: [UsageLimit] = []
    var observedAt: Date?
    var source: String = ""
    var state: SourceState = .needsConnection
    var detail: String?
    var extraInfo: String?

    var isStale: Bool {
        if case .stale = state { return true }
        return observedAt.map { Date().timeIntervalSince($0) > 300 } ?? false
    }
}
