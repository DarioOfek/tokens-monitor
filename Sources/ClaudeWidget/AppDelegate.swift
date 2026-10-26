import AppKit
import Combine
import SwiftUI

private final class PinnedWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var desktopWindow: NSWindow?
    private var usageSubscription: AnyCancellable?
    private var widgetHeight: CGFloat {
        min(570, max(500, (NSScreen.main?.visibleFrame.height ?? 570) - 24))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Tokens Monitor")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        usageSubscription = store.$usage.sink { [weak self] snapshots in
            self?.updateStatusItem(snapshots)
        }

        let popup = NSPopover()
        popup.behavior = .transient
        popup.contentSize = NSSize(width: 370, height: widgetHeight)
        popup.contentViewController = NSHostingController(rootView: ContentView(store: store, height: widgetHeight))
        popover = popup

        store.onPinChanged = { [weak self] pinned in self?.setPinned(pinned) }
        if store.pinned { setPinned(true) }
        store.refreshAll()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            store.refreshAll()
        }
    }

    private func setPinned(_ pinned: Bool) {
        if pinned {
            if desktopWindow == nil {
                let window = PinnedWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: widgetHeight),
                                      styleMask: [.borderless, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                window.level = .floating
                window.backgroundColor = .clear
                window.isOpaque = false
                window.hasShadow = true
                window.isMovableByWindowBackground = true
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.contentView = NSHostingView(rootView: ContentView(store: store, height: widgetHeight))
                if let saved = UserDefaults.standard.string(forKey: "widgetFrame") {
                    let frame = NSRectFromString(saved)
                    if frame != .zero {
                        window.setFrame(NSRect(origin: frame.origin, size: window.frame.size), display: false)
                    }
                    else { positionDefault(window) }
                } else { positionDefault(window) }
                NotificationCenter.default.addObserver(self, selector: #selector(savePosition),
                                                       name: NSWindow.didMoveNotification, object: window)
                desktopWindow = window
            }
            desktopWindow?.orderFront(nil)
        } else {
            desktopWindow?.orderOut(nil)
        }
    }

    private func updateStatusItem(_ snapshots: [Provider: ProviderUsage]) {
        let candidates = snapshots.values.filter { !$0.isStale }.flatMap { usage in
            usage.limits.map { (usage.provider, $0, usage.observedAt) }
        }.filter { _, _, observedAt in
            observedAt.map { Date().timeIntervalSince($0) < 300 } ?? false
        }
        guard let button = statusItem?.button else { return }
        guard let highest = candidates.max(by: { $0.1.usedPercent < $1.1.usedPercent }) else {
            button.title = " —"
            button.toolTip = "Tokens Monitor · Waiting for current account data"
            return
        }
        let shortName: String
        switch highest.0 {
        case .anthropic: shortName = "Claude"
        case .openAI: shortName = "Codex"
        case .xAI: shortName = "Grok"
        }
        button.title = " \(shortName) \(Int(highest.1.usedPercent.rounded()))%"
        button.toolTip = "\(highest.0.name) \(highest.1.label): \(Int(highest.1.usedPercent.rounded()))% used"
    }

    private func positionDefault(_ window: NSWindow) {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        window.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 385, y: frame.maxY))
    }

    @objc private func savePosition() {
        guard let desktopWindow else { return }
        UserDefaults.standard.set(NSStringFromRect(desktopWindow.frame), forKey: "widgetFrame")
    }
}
