import Foundation

enum CodexUsageService {
    static func refresh() async -> ProviderUsage {
        await Task.detached(priority: .utility) {
            if let result = readAppServer() { return result }
            if let result = readLatestSessionRecord() { return result }
            var result = ProviderUsage(provider: .openAI)
            result.state = .stale("Codex is unavailable. Sign in to Codex and refresh.")
            return result
        }.value
    }

    private static func readAppServer() -> ProviderUsage? {
        let paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        guard let binary = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardError = FileHandle.nullDevice
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        do { try process.run() } catch { return nil }

        let messages = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"tokens_monitor","title":"Tokens Monitor","version":"0.1.0"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(messages.utf8))

        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: timeout)
        var buffer = Data()
        var result: ProviderUsage?
        while process.isRunning && result == nil {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? Int == 2,
                      let payload = object["result"] as? [String: Any] else { continue }
                let bucket = payload["rateLimits"] as? [String: Any]
                if let bucket { result = makeUsage(bucket: bucket, observedAt: Date(), source: "Codex account") }
                break
            }
        }
        timeout.cancel()
        if process.isRunning { process.terminate() }
        input.fileHandleForWriting.closeFile()
        return result
    }

    private static func readLatestSessionRecord() -> ProviderUsage? {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var candidates: [(URL, Date)] = []
        for case let url as URL in files where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            candidates.append((url, date))
        }
        for (url, _) in candidates.sorted(by: { $0.1 > $1.1 }).prefix(8) {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n").reversed() {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let bucket = payload["rate_limits"] as? [String: Any],
                      let timestamp = object["timestamp"] as? String,
                      let observedAt = parseDate(timestamp),
                      let result = makeUsage(bucket: bucket, observedAt: observedAt, source: "Codex session record")
                else { continue }
                var stale = result
                stale.state = .stale("Last account reading came from a Codex session.")
                return stale
            }
        }
        return nil
    }

    private static func makeUsage(bucket: [String: Any], observedAt: Date, source: String) -> ProviderUsage? {
        var limits: [UsageLimit] = []
        for (key, fallbackLabel) in [("primary", "Current limit"), ("secondary", "Weekly limit")] {
            guard let window = bucket[key] as? [String: Any],
                  let percent = (window["usedPercent"] ?? window["used_percent"]) as? NSNumber else { continue }
            let minutes = (window["windowDurationMins"] ?? window["window_minutes"]) as? Int
            let label = minutes == 300 ? "5-hour limit" : minutes == 10080 ? "Weekly limit" : fallbackLabel
            let reset = (window["resetsAt"] ?? window["resets_at"]) as? NSNumber
            limits.append(UsageLimit(id: key, label: label, usedPercent: percent.doubleValue,
                                     resetAt: reset.map { Date(timeIntervalSince1970: $0.doubleValue) },
                                     resetDescription: nil))
        }
        guard !limits.isEmpty else { return nil }
        var result = ProviderUsage(provider: .openAI)
        result.limits = limits
        result.observedAt = observedAt
        result.source = source
        result.state = .fresh
        return result
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
