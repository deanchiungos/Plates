import Foundation
import Network
import OSLog
import SwiftData
import UIKit

/// TEMPORARY — a flight recorder for parties, for one round of field testing.
///
/// Parties keep failing on real phones in ways two simulators on one Mac cannot
/// show, and every fix so far has been reasoned from the code rather than read off
/// the failure. This writes everything the party transport does to a file on each
/// phone, so that after a bad drive every phone in the car can share its log and
/// `dev/tools/party_log_merge.py` can lay them side by side on one clock.
///
/// Three sources go into an exported log:
///
/// - **App events**, written as they happen to a JSON-lines file that survives
///   relaunches: every invitation, connection state, sighting of a peer, message
///   sent and received, reconnect attempt, network path change and app lifecycle
///   change, each stamped with wall time, uptime and a per-launch id.
/// - **The framework's own log.** MultipeerConnectivity runs inside the app's
///   process and logs its internals — channels, heartbeats, why a link died — to
///   the unified log. `OSLogStore` can read back the current process's entries,
///   so the export carries them too. Only for the current launch: share the log
///   *before* closing the app.
/// - **A snapshot** of the party's state at the moment of export, and at every
///   "Mark a problem" tap, so a tester can pin the moment it went wrong.
///
/// Nothing leaves the phone unless somebody taps Share. The log holds player
/// names, trip names and the party code, which is fine for a test build and is
/// the reason this must not ship to the App Store — see the release checklist.
///
/// To remove: delete this file, the diagnostics card in `PartyScreen`, and every
/// line that starts with `PartyDiagnostics.`.
enum PartyDiagnostics {

    // MARK: - Recording

    /// Records one event. Safe from any thread, including the framework's delegate
    /// queues, which is where the most useful events come from.
    static func record(_ event: String, _ fields: [String: String] = [:]) {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        recorder.queue.async { recorder.write(event, fields, at: now, uptime: uptime) }
    }

    /// Starts the always-on watchers — network path, app lifecycle, power — and
    /// writes the launch header. Called once, at launch.
    @MainActor
    static func start() {
        guard !started else { return }
        started = true
        record("launch", deviceFacts())

        let path = NWPathMonitor()
        path.pathUpdateHandler = { record("path", describe($0)) }
        path.start(queue: recorder.queue)
        pathMonitor = path

        let center = NotificationCenter.default
        let lifecycle: [(Notification.Name, String)] = [
            (UIApplication.didBecomeActiveNotification, "app.active"),
            (UIApplication.willResignActiveNotification, "app.resign"),
            (UIApplication.didEnterBackgroundNotification, "app.background"),
            (UIApplication.willEnterForegroundNotification, "app.foreground"),
            (UIApplication.willTerminateNotification, "app.terminate"),
            (UIApplication.didReceiveMemoryWarningNotification, "app.memoryWarning"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "device.locking"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "device.unlocked"),
            (Notification.Name.NSProcessInfoPowerStateDidChange, "power"),
            (ProcessInfo.thermalStateDidChangeNotification, "thermal"),
        ]
        for (name, label) in lifecycle {
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                record(label, ["lowPower": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
                               "thermal": thermal()])
            }
        }

        #if DEBUG
        // `-partyExportAfter 40` exports on its own after that many seconds and
        // copies the file to Documents/party-export.jsonl, so a simulator test can
        // collect both phones' logs without driving a share sheet.
        if let wait = LaunchFlags.value(after: "-partyExportAfter").flatMap(Double.init) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(wait))
                guard let url = await export() else { return }
                let docs = URL.documentsDirectory.appendingPathComponent("party-export.jsonl")
                try? FileManager.default.removeItem(at: docs)
                try? FileManager.default.copyItem(at: url, to: docs)
            }
        }
        #endif
    }

    /// A tester saying "it just went wrong", with the party's state at that moment.
    @MainActor
    static func mark() -> Date {
        var fields = PartySession.shared?.diagnosticState ?? ["party": "none"]
        fields["note"] = "marked by tester"
        record("MARK", fields)
        return Date()
    }

    // MARK: - Export

    /// Everything this phone knows, as one JSON-lines file ready to share.
    @MainActor
    static func export() async -> URL? {
        var header = deviceFacts()
        header["who"] = playerName()
        header["exportedAt"] = stamp(Date())
        header["launch"] = recorder.launch
        let state = PartySession.shared?.diagnosticState ?? ["party": "none"]
        record("export", state)

        // Let the queue flush the line just written before the file is read.
        let files: [URL] = await withCheckedContinuation { done in
            recorder.queue.async {
                recorder.handle?.synchronizeFile()
                done.resume(returning: [recorder.previousURL, recorder.currentURL])
            }
        }
        let name = (header["who"] ?? "phone").filter { $0.isLetter || $0.isNumber }
        let launchedAt = launchDate

        return await Task.detached(priority: .userInitiated) {
            var out = ""
            out += line(["src": "meta"].merging(header) { $1 })
            for file in files {
                if let text = try? String(contentsOf: file, encoding: .utf8) { out += text }
            }
            out += systemLog(since: launchedAt)

            let stampName = ISO8601DateFormatter.string(
                from: Date(), timeZone: .current,
                formatOptions: [.withYear, .withMonth, .withDay, .withTime])
                .replacingOccurrences(of: ":", with: "")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("party-log-\(name.isEmpty ? "phone" : name)-\(stampName).jsonl")
            do {
                try out.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                return nil
            }
        }.value
    }

    /// Wipes the file, for starting a fresh test with nothing from the last one.
    static func clear() {
        recorder.queue.async { recorder.reset() }
        record("cleared")
    }

    // MARK: - The framework's log

    /// The current process's MultipeerConnectivity and networking entries since
    /// launch, newest 80,000 (about an hour of heartbeats), as JSON lines.
    private static func systemLog(since: Date) -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            return line(["src": "meta", "ev": "oslog.unavailable"])
        }
        let wanted = NSPredicate(format:
            "subsystem BEGINSWITH 'com.apple.multipeerconnectivity' OR subsystem == 'com.apple.network'")
        guard let entries = try? store.getEntries(at: store.position(date: since),
                                                   matching: wanted) else {
            return line(["src": "meta", "ev": "oslog.failed"])
        }
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            lines.append(line([
                "t": stamp(entry.date),
                "src": "os",
                "sub": entry.subsystem,
                "cat": entry.category,
                "lvl": "\(entry.level.rawValue)",
                "msg": entry.composedMessage,
            ]))
        }
        let kept = lines.suffix(80_000)
        var out = line(["src": "meta", "ev": "oslog",
                        "entries": "\(lines.count)", "kept": "\(kept.count)"])
        out += kept.joined()
        return out
    }

    // MARK: - Facts

    private static func deviceFacts() -> [String: String] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "model": model,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "app": "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))",
            "lowPower": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
            "thermal": thermal(),
            "tz": TimeZone.current.identifier,
        ]
    }

    @MainActor
    private static func playerName() -> String {
        let players = (try? PlatesStore.context.fetch(FetchDescriptor<Player>())) ?? []
        return DevicePlayer.resolve(from: players)?.name ?? "unknown"
    }

    private static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    /// Everything a network path can say about itself. The question this answers is
    /// which of Wi-Fi, cellular and the rest the phone had at the moment a party
    /// failed — the field report was "Wi-Fi no, cellular yes".
    private static func describe(_ path: NWPath) -> [String: String] {
        let status: String = switch path.status {
        case .satisfied: "satisfied"
        case .unsatisfied: "unsatisfied"
        case .requiresConnection: "requiresConnection"
        @unknown default: "unknown"
        }
        let kinds: [(NWInterface.InterfaceType, String)] = [
            (.wifi, "wifi"), (.cellular, "cellular"), (.wiredEthernet, "wired"),
            (.loopback, "loopback"), (.other, "other"),
        ]
        let using = kinds.filter { path.usesInterfaceType($0.0) }.map(\.1)
        let available = path.availableInterfaces.map { "\($0.name):\($0.type)" }
        return [
            "status": status,
            "using": using.joined(separator: ","),
            "interfaces": available.joined(separator: ","),
            "expensive": "\(path.isExpensive)",
            "constrained": "\(path.isConstrained)",
            "ipv4": "\(path.supportsIPv4)",
            "dns": "\(path.supportsDNS)",
        ]
    }

    // MARK: - Machinery

    @MainActor private static var started = false
    @MainActor private static var pathMonitor: NWPathMonitor?
    @MainActor private static let launchDate = Date()

    fileprivate static let recorder = Recorder()

    fileprivate static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: TimeZone(identifier: "UTC")!,
                                    formatOptions: [.withInternetDateTime,
                                                    .withFractionalSeconds])
    }

    fileprivate static func line(_ fields: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: fields,
                                                     options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text + "\n"
    }
}

/// The file, owned by one serial queue. Every touch of the handle happens on
/// `queue`, which is what makes the unchecked `Sendable` honest.
private final class Recorder: @unchecked Sendable {
    let queue = DispatchQueue(label: "party.diagnostics", qos: .utility)
    let launch = String(UUID().uuidString.prefix(4))
    let currentURL: URL
    let previousURL: URL
    var handle: FileHandle?
    private var seq = 0
    private var written = 0

    /// Rolled over at this size, keeping one previous file, so a long test cannot
    /// fill the phone and the export still reaches back past a relaunch or two.
    private let limit = 4_000_000

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.temporaryDirectory
        var folder = base.appendingPathComponent("PartyDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        currentURL = folder.appendingPathComponent("party.jsonl")
        previousURL = folder.appendingPathComponent("party.1.jsonl")
        queue.async { self.open() }
    }

    private func open() {
        if !FileManager.default.fileExists(atPath: currentURL.path) {
            FileManager.default.createFile(atPath: currentURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: currentURL)
        written = Int((try? handle?.seekToEnd()) ?? 0)
    }

    func write(_ event: String, _ fields: [String: String], at date: Date, uptime: TimeInterval) {
        seq += 1
        var all = fields
        all["t"] = PartyDiagnostics.stamp(date)
        all["up"] = String(format: "%.3f", uptime)
        all["ev"] = event
        all["src"] = "app"
        all["launch"] = launch
        all["seq"] = "\(seq)"
        let text = PartyDiagnostics.line(all)
        guard let data = text.data(using: .utf8) else { return }
        if written + data.count > limit { rotate() }
        handle?.write(data)
        written += data.count
    }

    private func rotate() {
        try? handle?.close()
        try? FileManager.default.removeItem(at: previousURL)
        try? FileManager.default.moveItem(at: currentURL, to: previousURL)
        open()
    }

    func reset() {
        try? handle?.close()
        try? FileManager.default.removeItem(at: previousURL)
        try? FileManager.default.removeItem(at: currentURL)
        open()
    }
}

extension PartyEnvelope.Payload {
    /// What a message was, for the log, without its contents.
    var diagnosticSummary: String {
        switch self {
        case .hello(let s):
            "hello(sightings:\(s.sightings.count) players:\(s.players.count) tombstones:\(s.tombstones.count))"
        case .sighting(let e): "sighting(\(e.plateCode))"
        case .remove(let e): "remove(\(e.sightingIDs.count))"
        case .roster(let p): "roster(\(p.count))"
        case .tripUpdate: "tripUpdate"
        case .bye: "bye"
        }
    }
}
