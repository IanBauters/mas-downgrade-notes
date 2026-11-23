import Foundation
import AppKit

enum StepState {
    case idle, running, ok, warning, failed
}

struct CheckResult {
    var state: StepState = .idle
    var detail: String = ""
}

struct AppInfo {
    var name: String
    var fileBaseName: String
    var version: String
    var build: String
    var bundleID: String
    var minimumSystem: String?
    var appURL: URL
}

@MainActor
final class Pipeline: ObservableObject {
    // Capture
    @Published var watching = false
    @Published var watchStatus = "Not watching."
    @Published var capturedBytes: Int64 = 0

    // Package and checks
    @Published var pkgURL: URL?
    @Published var signature = CheckResult()
    @Published var gatekeeper = CheckResult()
    @Published var contents = CheckResult()
    @Published var archive = CheckResult()
    @Published var install = CheckResult()
    @Published var verify = CheckResult()
    @Published var appInfo: AppInfo?
    @Published var archivedURL: URL?
    @Published var installedURL: URL?
    @Published var canInstall = false
    @Published var busy = false
    @Published var log = ""

    @Published var archiveFolder: URL {
        didSet { UserDefaults.standard.set(archiveFolder.path, forKey: "archiveFolder") }
    }

    @Published var alwaysAdmin: Bool = UserDefaults.standard.bool(forKey: "alwaysAdmin") {
        didSet { UserDefaults.standard.set(alwaysAdmin, forKey: "alwaysAdmin") }
    }

    let staging: URL
    private var capturedURL: URL { staging.appendingPathComponent("captured.pkg") }
    private var linkURL: URL { staging.appendingPathComponent("capture.link") }
    private var markerURL: URL { staging.appendingPathComponent("marker") }
    private var stopURL: URL { staging.appendingPathComponent("stop") }
    private var statusURL: URL { staging.appendingPathComponent("status") }
    private var scriptURL: URL { staging.appendingPathComponent("watch.sh") }

    private var pollTask: Task<Void, Never>?
    private var expandedDir: URL?
    private let fm = FileManager.default

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        staging = caches.appendingPathComponent("Keeper", isDirectory: true)
        if let saved = UserDefaults.standard.string(forKey: "archiveFolder") {
            archiveFolder = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            archiveFolder = docs.appendingPathComponent("App Store Packages", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        purgeStaging(includingExpanded: true)
    }

    // MARK: - Capture

    func startWatching(asAdmin forceAdmin: Bool = false) {
        guard !watching else { return }
        resetResults()
        purgeStaging(includingExpanded: false)
        try? fm.removeItem(at: capturedURL)

        do {
            try WatcherScript.source.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            watchStatus = "Could not prepare the watcher: \(error.localizedDescription)"
            return
        }
        fm.createFile(atPath: markerURL.path, contents: Data())

        let base = Self.appStoreCacheFolder()
        let admin = forceAdmin || alwaysAdmin || cacheNeedsAdmin(base)
        let args = [scriptURL.path, base.path, capturedURL.path, staging.path, admin ? String(getuid()) : ""]

        watching = true
        capturedBytes = 0
        watchStatus = admin
            ? "Waiting for the administrator password…"
            : "Waiting for an App Store download. Start the download now."
        appendLog("Watching \(base.path)\(admin ? " (as administrator)" : "")")
        startPolling()

        if admin {
            let command = (["/bin/sh"] + args).map(Shell.quote).joined(separator: " ")
            Task {
                let result = await Shell.runAsAdmin(command, prompt: "Keeper needs administrator rights to read the App Store download folder.")
                self.watchFinished(result, admin: true)
            }
        } else {
            Task {
                let result = await Shell.run("/bin/sh", args)
                self.watchFinished(result, admin: false)
            }
        }
    }

    func stopWatching() {
        fm.createFile(atPath: stopURL.path, contents: Data())
        watchStatus = "Stopping…"
    }

    private func watchFinished(_ result: ShellResult, admin: Bool) {
        pollTask?.cancel()
        pollTask = nil
        watching = false
        let state = readStatus().state

        switch state {
        case "done":
            watchStatus = "Download captured."
            appendLog("Captured package (\(ByteCountFormatter.string(fromByteCount: fileSize(capturedURL), countStyle: .file))).")
            open(capturedURL, captured: true)
        case "stopped":
            watchStatus = "Stopped."
        case "timeout":
            watchStatus = "Stopped after 2 hours without a download."
        case "noaccess":
            if admin {
                watchStatus = "Cannot read the App Store download folder, even as administrator."
            } else {
                appendLog("No access to the App Store download folder. Restarting as administrator.")
                alwaysAdmin = true
                startWatching(asAdmin: true)
            }
        case "copyfailed":
            watchStatus = "The download was found, but Keeper could not copy it."
        default:
            if result.output.contains("-128") {
                watchStatus = "Cancelled."
            } else {
                watchStatus = "The watcher stopped unexpectedly. See the log."
                appendLog(result.output)
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollOnce()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func pollOnce() {
        let status = readStatus()
        let size = [linkURL, capturedURL, URL(fileURLWithPath: capturedURL.path + ".tmp")]
            .map(fileSize)
            .max() ?? 0
        capturedBytes = size
        let name = (status.path as NSString).lastPathComponent
        let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        switch status.state {
        case "waiting":
            watchStatus = "Waiting for an App Store download. Start the download now."
        case "found", "link":
            watchStatus = "Downloading \(name): \(sizeText). Keep the App Store open until it finishes."
        case "copy":
            watchStatus = "Downloading \(name): \(sizeText) (copy mode). Keep the App Store open until it finishes."
        default:
            break
        }
    }

    private func readStatus() -> (state: String, path: String) {
        guard let text = try? String(contentsOf: statusURL, encoding: .utf8) else { return ("", "") }
        let line = text.trimmed
        if let space = line.firstIndex(of: " ") {
            return (String(line[..<space]), String(line[line.index(after: space)...]))
        }
        return (line, "")
    }

    private func cacheNeedsAdmin(_ base: URL) -> Bool {
        for dir in [base.deletingLastPathComponent(), base] {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue,
               (try? fm.contentsOfDirectory(atPath: dir.path)) == nil {
                return true
            }
        }
        return false
    }

    nonisolated static func appStoreCacheFolder() -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count)
        let root = length > 0
            ? buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            : NSTemporaryDirectory()
        return URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("com.apple.appstoreagent", isDirectory: true)
            .appendingPathComponent("com.apple.appstore", isDirectory: true)
    }

    // MARK: - Check, extract, archive

    func openPackage(_ url: URL) {
        open(url, captured: false)
    }

    private func open(_ url: URL, captured: Bool) {
        resetResults()
        pkgURL = url
        busy = true
        Task {
            await processPackage(url, captured: captured)
            busy = false
        }
    }

    private func processPackage(_ url: URL, captured: Bool) async {
        // 1. Signature
        signature = CheckResult(state: .running, detail: "Checking…")
        let sig = await Shell.run("/usr/sbin/pkgutil", ["--check-signature", url.path])
        appendLog("$ pkgutil --check-signature\n\(sig.output.trimmed)")
        let statusLine = sig.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Status:") }
            .map { String($0.dropFirst("Status:".count)).trimmed } ?? "No signature found."
        if sig.status == 0 && statusLine.contains("Apple") {
            signature = CheckResult(state: .ok, detail: statusLine)
        } else if sig.status == 0 {
            signature = CheckResult(state: .warning, detail: "\(statusLine) (not signed by Apple)")
        } else {
            signature = CheckResult(state: .failed, detail: "\(statusLine) The package is damaged or incomplete.")
            return
        }

        // 2. Gatekeeper (for information: App Store packages can be accepted here and still be refused by the installer)
        gatekeeper = CheckResult(state: .running, detail: "Checking…")
        let gk = await Shell.run("/usr/sbin/spctl", ["--assess", "--type", "install", "-vvv", url.path])
        appendLog("$ spctl --assess --type install\n\(gk.output.trimmed)")
        let source = gk.output
            .split(separator: "\n")
            .first { $0.hasPrefix("source=") }
            .map { String($0.dropFirst("source=".count)) } ?? "unknown source"
        gatekeeper = gk.status == 0
            ? CheckResult(state: .ok, detail: "Accepted (\(source))")
            : CheckResult(state: .warning, detail: "Rejected (\(source)). Keeper can still install the app.")

        // 3. Extract and read the app
        contents = CheckResult(state: .running, detail: "Extracting the package. This can take a few minutes…")
        let dir = staging.appendingPathComponent("expanded-\(UUID().uuidString)", isDirectory: true)
        expandedDir = dir
        let ex = await Shell.run("/usr/sbin/pkgutil", ["--expand-full", url.path, dir.path])
        if ex.status != 0 {
            contents = CheckResult(state: .failed, detail: "Could not extract the package: \(ex.output.trimmed)")
            return
        }
        guard let app = await Task.detached(operation: { Pipeline.findApp(in: dir) }).value else {
            contents = CheckResult(state: .failed, detail: "There is no app in this package.")
            return
        }
        appendLog("Found \(app.path)")

        let info = Self.readInfo(app)
        appInfo = info
        canInstall = true

        var detail = "\(info.name) \(info.version) (\(info.bundleID))"
        if let minimum = info.minimumSystem {
            if Self.isCompatible(minimum: minimum) {
                detail += ". Needs macOS \(minimum) or later."
                contents = CheckResult(state: .ok, detail: detail)
            } else {
                detail += ". Needs macOS \(minimum) or later. This Mac has macOS \(Self.currentSystem())."
                contents = CheckResult(state: .warning, detail: detail)
            }
        } else {
            contents = CheckResult(state: .ok, detail: detail)
        }

        // 4. Archive (only for packages Keeper captured itself)
        guard captured else {
            archive = CheckResult(state: .idle, detail: "Opened from \(url.deletingLastPathComponent().path). Not copied.")
            return
        }
        archive = CheckResult(state: .running, detail: "Saving to the archive…")
        let folder = archiveFolder
        let fileName = "\(info.fileBaseName) \(info.version).pkg"
        let moved = await Task.detached(operation: { () -> Result<URL, Error> in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = Pipeline.uniqueURL(folder.appendingPathComponent(fileName))
                try FileManager.default.moveItem(at: url, to: dest)
                return .success(dest)
            } catch {
                return .failure(error)
            }
        }).value

        switch moved {
        case .success(let dest):
            archivedURL = dest
            pkgURL = dest
            Self.writeSidecar(for: dest, info: info, signature: statusLine)
            archive = CheckResult(state: .ok, detail: dest.path)
            appendLog("Saved \(dest.path)")
        case .failure(let error):
            archive = CheckResult(state: .failed, detail: "Could not save to the archive: \(error.localizedDescription) The package is still at \(url.path).")
        }
    }

    // MARK: - Install

    func installApp() {
        guard let info = appInfo, canInstall, !busy else { return }
        busy = true
        Task {
            await doInstall(info)
            busy = false
        }
    }

    private func doInstall(_ info: AppInfo) async {
        install = CheckResult(state: .running, detail: "Waiting for the administrator password…")
        verify = CheckResult()

        let target = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(info.appURL.lastPathComponent)
        var commands: [String] = []
        var backupNote = ""

        if fm.fileExists(atPath: target.path) {
            let oldVersion = Self.version(of: target) ?? "old"
            let backup = Self.uniqueURL(
                target.deletingLastPathComponent()
                    .appendingPathComponent("\(target.deletingPathExtension().lastPathComponent) \(oldVersion).app")
            )
            commands.append("/bin/mv \(Shell.quote(target.path)) \(Shell.quote(backup.path))")
            backupNote = " The previous version is now \(backup.lastPathComponent)."
        }
        commands.append("/usr/bin/ditto \(Shell.quote(info.appURL.path)) \(Shell.quote(target.path))")
        commands.append("/usr/sbin/chown -R root:wheel \(Shell.quote(target.path))")
        commands.append("/bin/chmod -R go-w \(Shell.quote(target.path))")

        appendLog("Installing to \(target.path)")
        let result = await Shell.runAsAdmin(
            commands.joined(separator: " && "),
            prompt: "Keeper wants to install \(info.name) \(info.version) in the Applications folder."
        )

        if result.status != 0 {
            appendLog(result.output.trimmed)
            if result.output.contains("-128") {
                install = CheckResult(state: .failed, detail: "Cancelled.")
            } else if result.output.contains("Operation not permitted") {
                install = CheckResult(state: .failed, detail: "macOS blocked the change. Allow Keeper in System Settings > Privacy & Security > App Management, then try again.")
            } else {
                install = CheckResult(state: .failed, detail: "Install failed: \(result.output.trimmed)")
            }
            return
        }

        install = CheckResult(state: .ok, detail: "Installed in \(target.path).\(backupNote)")
        installedURL = target

        verify = CheckResult(state: .running, detail: "Checking the code signature. This can take a minute…")
        let cs = await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
        let installedVersion = Self.version(of: target) ?? "unknown"
        if cs.status == 0 {
            verify = CheckResult(state: .ok, detail: "Signature is valid. Installed version: \(installedVersion).")
        } else {
            verify = CheckResult(state: .failed, detail: "Signature check failed: \(cs.output.trimmed)")
            appendLog(cs.output.trimmed)
        }

        cleanupExpanded()
    }

    // MARK: - Housekeeping

    private func resetResults() {
        pkgURL = nil
        signature = CheckResult()
        gatekeeper = CheckResult()
        contents = CheckResult()
        archive = CheckResult()
        install = CheckResult()
        verify = CheckResult()
        appInfo = nil
        archivedURL = nil
        installedURL = nil
        canInstall = false
        cleanupExpanded()
    }

    private func cleanupExpanded() {
        canInstall = false
        guard let dir = expandedDir else { return }
        expandedDir = nil
        Task.detached { try? FileManager.default.removeItem(at: dir) }
    }

    private func purgeStaging(includingExpanded: Bool) {
        let small = ["capture.link", "marker", "stop", "status", "watch.sh", "captured.pkg.tmp", "find.err", "existing"]
        for name in small {
            try? fm.removeItem(at: staging.appendingPathComponent(name))
        }
        guard includingExpanded else { return }
        let dir = staging
        Task.detached {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where name.hasPrefix("expanded-") {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    private func appendLog(_ text: String) {
        guard !text.isEmpty else { return }
        log += text + "\n"
        if log.count > 60_000 { log = String(log.suffix(40_000)) }
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    // MARK: - Helpers

    nonisolated static func findApp(in dir: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        var found: [URL] = []
        while let url = walker.nextObject() as? URL {
            if url.pathExtension == "app" {
                found.append(url)
                walker.skipDescendants()
            } else if walker.level > 6 {
                walker.skipDescendants()
            }
        }
        return found.first { $0.path.contains("/Payload/") } ?? found.first
    }

    nonisolated static func readInfo(_ app: URL) -> AppInfo {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let info = (NSDictionary(contentsOf: plist) as? [String: Any]) ?? [:]
        let fileBaseName = app.deletingPathExtension().lastPathComponent
        return AppInfo(
            name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fileBaseName,
            fileBaseName: fileBaseName,
            version: (info["CFBundleShortVersionString"] as? String) ?? "unknown",
            build: (info["CFBundleVersion"] as? String) ?? "",
            bundleID: (info["CFBundleIdentifier"] as? String) ?? "unknown",
            minimumSystem: info["LSMinimumSystemVersion"] as? String,
            appURL: app
        )
    }

    nonisolated static func version(of app: URL) -> String? {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return info?["CFBundleShortVersionString"] as? String
    }

    nonisolated static func isCompatible(minimum: String) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(
            majorVersion: parts.count > 0 ? parts[0] : 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
    }

    nonisolated static func currentSystem() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
    }

    nonisolated static func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// Writes "<name> <version>.json" next to the archived package, for the software archive.
    nonisolated static func writeSidecar(for pkg: URL, info: AppInfo, signature: String) {
        let dict: [String: Any] = [
            "name": info.name,
            "version": info.version,
            "build": info.build,
            "bundleIdentifier": info.bundleID,
            "minimumSystemVersion": info.minimumSystem ?? "",
            "signature": signature,
            "package": pkg.lastPathComponent,
            "capturedAt": ISO8601DateFormatter().string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: pkg.deletingPathExtension().appendingPathExtension("json"))
    }
}
