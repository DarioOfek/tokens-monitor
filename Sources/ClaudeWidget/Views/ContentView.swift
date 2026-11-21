import SwiftUI

struct ContentView: View {
    @ObservedObject var store: UsageStore
    let height: CGFloat

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 18)
            Color.black.opacity(0.6)
            ScrollView {
                VStack(spacing: 7) {
                    header
                    ForEach(Provider.allCases) { provider in
                        ProviderCard(usage: store.usage[provider] ?? ProviderUsage(provider: provider),
                                     openAccount: { store.openAccountPage(for: provider) })
                    }
                    Text("All bars show usage consumed · Refreshes every 90 seconds")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.48))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(10)
            }
        }
        .frame(width: 370, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.white)
            Text("Tokens Monitor")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button { store.refreshAll() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 45 : 0))
            }
            .help("Refresh now")
            Button { store.togglePinned() } label: {
                Image(systemName: store.pinned ? "pin.fill" : "pin")
            }
            .help(store.pinned ? "Unpin desktop card" : "Pin desktop card")
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "xmark")
            }
            .help("Quit")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

private struct ProviderCard: View {
    let usage: ProviderUsage
    let openAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                ProviderIcon(provider: usage.provider)
                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.provider.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(usage.provider.vendor)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if usage.isStale {
                    Text("STALE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Button(action: openAccount) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
                .help("Open \(usage.provider.vendor) account page")
            }

            if usage.limits.isEmpty {
                HStack {
                    Text(emptyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.68))
                    Spacer()
                    if usage.provider != .openAI {
                        Button("Connect", action: openAccount)
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                ForEach(usage.limits) { limit in
                    LimitBar(limit: limit)
                }
            }

            if let extraInfo = usage.extraInfo {
                Text(extraInfo)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack {
                Text(footer)
                    .lineLimit(1)
                Spacer()
                if usage.isStale && usage.provider != .openAI {
                    Button("Reconnect", action: openAccount)
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.8))
                }
                if let date = usage.observedAt {
                    Text(date, style: .relative)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.48))
        }
        .padding(10)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))
    }

    private var emptyMessage: String {
        switch usage.state {
        case .loading: "Loading account usage…"
        case .needsConnection: "Connect to view account usage"
        case .stale(let message): message
        case .fresh: "No limit data available"
        }
    }

    private var footer: String {
        if let detail = usage.detail { return detail }
        return usage.source.isEmpty ? "Waiting for account data" : usage.source
    }
}

private struct ProviderIcon: View {
    let provider: Provider

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: iconName, withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text(String(provider.vendor.prefix(1)))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("\(provider.vendor) icon")
    }

    private var iconName: String {
        switch provider {
        case .anthropic: "anthropic"
        case .openAI: "openai"
        case .xAI: "xai"
        }
    }
}
