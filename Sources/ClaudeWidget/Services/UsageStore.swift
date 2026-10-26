import AppKit
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage: [Provider: ProviderUsage] = Dictionary(
        uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderUsage(provider: $0)) }
    )
    @Published private(set) var isRefreshing = false
    @Published var pinned = UserDefaults.standard.bool(forKey: "pinnedWidget")

    var onPinChanged: ((Bool) -> Void)?
    private let claude = AccountPageUsageService(provider: .anthropic)
    private let grok = AccountPageUsageService(provider: .xAI)
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        claude.onUpdate = { [weak self] value in self?.usage[.anthropic] = value }
        grok.onUpdate = { [weak self] value in self?.usage[.xAI] = value }
        usage[.anthropic] = claude.currentUsage
        usage[.xAI] = grok.currentUsage
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        })
    }

    func refreshAll() {
        claude.refresh()
        grok.refresh()
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            usage[.openAI] = await CodexUsageService.refresh()
            isRefreshing = false
        }
    }

    func openAccountPage(for provider: Provider) {
        switch provider {
        case .anthropic: claude.openAccountPage()
        case .xAI: grok.openAccountPage()
        case .openAI: NSWorkspace.shared.open(URL(string: "https://chatgpt.com/settings/usage")!)
        }
    }

    func togglePinned() {
        pinned.toggle()
        UserDefaults.standard.set(pinned, forKey: "pinnedWidget")
        onPinChanged?(pinned)
    }
}
