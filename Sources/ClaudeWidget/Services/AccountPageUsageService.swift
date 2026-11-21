import AppKit
import WebKit

enum AccountPageParser {
    static func parse(_ provider: Provider, text: String) -> ProviderUsage? {
        let normalized = text.replacingOccurrences(of: "\r", with: "")
        var limits: [UsageLimit] = []
        switch provider {
        case .anthropic:
            guard let session = section(normalized, after: "Current session", before: "Weekly limits"),
                  let sessionPercent = usedPercent(in: session) else { return nil }
            limits.append(UsageLimit(id: "session", label: "Current session", usedPercent: sessionPercent,
                                     resetAt: nil, resetDescription: resetLine(in: session)))
            if let weekly = section(normalized, after: "All models", before: "Limit resets"),
               let weeklyPercent = usedPercent(in: weekly) {
                limits.append(UsageLimit(id: "weekly", label: "Weekly limit", usedPercent: weeklyPercent,
                                         resetAt: nil, resetDescription: resetLine(in: weekly)))
            }
        case .xAI:
            guard let plan = section(normalized, after: "Current plan", before: "Account balance") ??
                    section(normalized, after: "Current plan", before: "Payment details") ??
                    section(normalized, after: "Renews", before: "Additional usage"),
                  let percent = usedPercent(in: plan) else { return nil }
            limits.append(UsageLimit(id: "weekly", label: "Weekly included usage", usedPercent: percent,
                                     resetAt: nil, resetDescription: resetLine(in: plan)))
        case .openAI:
            return nil
        }
        var result = ProviderUsage(provider: provider)
        result.limits = limits
        result.observedAt = Date()
        result.source = "Account page"
        result.state = .fresh
        if provider == .xAI,
           let credits = section(normalized, after: "Credit balance", before: "Payment details") ??
                        section(normalized, after: "Credits available", before: "Payment details") {
            let firstValue = credits.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.hasPrefix("$") }
            if let firstValue { result.extraInfo = "Credits available \(firstValue)" }
        }
        return result
    }

    private static func section(_ text: String, after anchor: String, before end: String) -> String? {
        guard let start = text.range(of: anchor, options: .caseInsensitive) else { return nil }
        let tail = text[start.upperBound...]
        let stop = tail.range(of: end, options: .caseInsensitive)?.lowerBound ?? text.endIndex
        return String(tail[..<stop])
    }

    private static func usedPercent(in text: String) -> Double? {
        let pattern = #"(\d{1,3}(?:\.\d+)?)\s*%\s*used"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]), value >= 0, value <= 100 else { return nil }
        return value
    }

    private static func resetLine(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = trimmed.range(of: "Resets", options: .caseInsensitive) {
                return String(trimmed[range.lowerBound...])
            }
        }
        return nil
    }
}

private struct SavedAccountUsage: Codable {
    struct Limit: Codable {
        let id: String
        let label: String
        let usedPercent: Double
        let resetAt: Date?
        let resetDescription: String?
    }

    let limits: [Limit]
    let observedAt: Date
    let extraInfo: String?

    init(_ usage: ProviderUsage) {
        limits = usage.limits.map {
            Limit(id: $0.id, label: $0.label, usedPercent: $0.usedPercent,
                  resetAt: $0.resetAt, resetDescription: $0.resetDescription)
        }
        observedAt = usage.observedAt ?? Date()
        extraInfo = usage.extraInfo
    }

    func asUsage(for provider: Provider) -> ProviderUsage {
        var usage = ProviderUsage(provider: provider)
        usage.limits = limits.map {
            UsageLimit(id: $0.id, label: $0.label, usedPercent: $0.usedPercent,
                       resetAt: $0.resetAt, resetDescription: $0.resetDescription)
        }
        usage.observedAt = observedAt
        usage.extraInfo = extraInfo
        usage.source = "Last account reading"
        usage.state = .stale("Refreshing account page…")
        return usage
    }
}

@MainActor
final class AccountPageUsageService: NSObject, WKNavigationDelegate, WKUIDelegate {
    let provider: Provider
    var onUpdate: ((ProviderUsage) -> Void)?
    var currentUsage: ProviderUsage { lastUsage }
    private let webView: WKWebView
    private var window: NSWindow?
    private var popupWindows: [ObjectIdentifier: NSWindow] = [:]
    private var lastUsage: ProviderUsage
    private var navigationID = 0

    init(provider: Provider) {
        self.provider = provider
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        if let data = UserDefaults.standard.data(forKey: "accountUsage.\(provider.rawValue)"),
           let saved = try? JSONDecoder().decode(SavedAccountUsage.self, from: data) {
            lastUsage = saved.asUsage(for: provider)
        } else {
            lastUsage = ProviderUsage(provider: provider)
        }
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    private func prepareWindow() {
        if window == nil {
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                                     styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                     backing: .buffered, defer: false)
            newWindow.title = "Connect \(provider.vendor)"
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = webView
            newWindow.center()
            window = newWindow
        }
    }

    func openAccountPage() {
        prepareWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        refresh(force: true)
    }

    func refresh(force: Bool = false) {
        guard let url = provider.accountURL else { return }
        prepareWindow()
        // Let the user finish authentication without a timer reloading the form.
        if window?.isVisible == true && !force { return }
        navigationID += 1
        if lastUsage.limits.isEmpty {
            lastUsage.state = .loading
            onUpdate?(lastUsage)
        }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let id = navigationID
        for delay in [2.0, 6.0, 12.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.navigationID == id else { return }
                self.readPage(finalAttempt: delay == 12.0)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        markUnavailable("Could not load the account page.")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        markUnavailable("Could not load the account page.")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        let popupWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 690),
                                   styleMask: [.titled, .closable, .resizable],
                                   backing: .buffered, defer: false)
        popupWindow.title = "Sign in to \(provider.vendor)"
        popupWindow.contentView = popup
        popupWindow.isReleasedWhenClosed = false
        popupWindow.center()
        popupWindow.makeKeyAndOrderFront(nil)
        popupWindows[ObjectIdentifier(popup)] = popupWindow
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupWindows.removeValue(forKey: ObjectIdentifier(webView))?.close()
        refresh(force: true)
    }

    private func readPage(finalAttempt: Bool) {
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String, let usage = AccountPageParser.parse(self.provider, text: text) {
                self.lastUsage = usage
                if let data = try? JSONEncoder().encode(SavedAccountUsage(usage)) {
                    UserDefaults.standard.set(data, forKey: "accountUsage.\(self.provider.rawValue)")
                }
                self.onUpdate?(usage)
            } else if finalAttempt {
                self.markUnavailable("Sign in or open the usage page to reconnect.")
            }
        }
    }

    private func markUnavailable(_ message: String) {
        lastUsage.state = lastUsage.limits.isEmpty ? .needsConnection : .stale(message)
        lastUsage.detail = message
        onUpdate?(lastUsage)
    }
}
