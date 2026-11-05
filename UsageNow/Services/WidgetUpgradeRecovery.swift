import CoreServices
import Darwin
import Foundation
import Security
import WidgetKit

/// Rebinds the installed widget once after an app replacement. WidgetKit can
/// otherwise keep an old extension alive while reading the new bundle's files.
/// This never resets widget placements, snapshots, provider settings, or system
/// widget processes. Development/archive copies must not register themselves.
@MainActor
final class WidgetUpgradeRecovery {
    static let completedBuildKey = "widget.registeredInstallation.v1"
    private let defaults: UserDefaults
    private var isRunning = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func start() {
        guard let installation = WidgetInstallation(bundle: .main) else { return }
        Task { [self] in
            await recover(installation: installation, repair: { installation in
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        continuation.resume(returning: installation.repair())
                    }
                }
            }, reload: {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
            }, pause: { try? await Task.sleep(for: .seconds(3)) })
        }
    }

    /// Injectable effects keep regression tests away from installed widgets.
    func recover(
        installation: WidgetInstallation,
        repair: (WidgetInstallation) async -> Bool,
        reload: () -> Void,
        pause: () async -> Void
    ) async {
        guard !isRunning, defaults.string(forKey: Self.completedBuildKey) != installation.key else { return }
        isRunning = true
        defer { isRunning = false }
        guard await repair(installation) else {
            Log.app.error("Widget upgrade registration failed; will retry on the next app launch")
            return
        }
        // Registration is asynchronous inside macOS. Request a new timeline
        // after it settles, then once more for the startup provider refresh.
        await pause()
        reload()
        await pause()
        reload()
        defaults.set(installation.key, forKey: Self.completedBuildKey)
        Log.app.notice("Widget upgrade registration completed for build \(installation.build, privacy: .public)")
    }
}

struct WidgetInstallation: Sendable {
    let appURL: URL
    let extensionURL: URL
    let executableURL: URL
    let build: String
    let teamIdentifier: String?
    var key: String { appURL.path + ":" + build }

    init?(bundle: Bundle) {
        let appURL = bundle.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard Self.isInstalledApp(appURL, homeDirectory: home),
              bundle.bundleIdentifier == "com.usagenow.UsageNow",
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty,
              let extensionURL = bundle.builtInPlugInsURL?.appending(path: "UsageNowWidget.appex"),
              let widget = Bundle(url: extensionURL),
              widget.bundleIdentifier == "com.usagenow.UsageNow.Widget",
              widget.object(forInfoDictionaryKey: "CFBundleVersion") as? String == build,
              let executableURL = widget.executableURL else { return nil }
        let group = bundle.object(forInfoDictionaryKey: "UsageNowAppGroupIdentifier") as? String
        let team = group?.split(separator: ".").first.map(String.init)
        self.init(appURL: appURL, extensionURL: extensionURL, executableURL: executableURL, build: build, teamIdentifier: team)
    }

    init(appURL: URL, extensionURL: URL, executableURL: URL, build: String, teamIdentifier: String? = nil) {
        self.appURL = appURL
        self.extensionURL = extensionURL
        self.executableURL = executableURL
        self.build = build
        self.teamIdentifier = teamIdentifier
    }

    static func isInstalledApp(_ url: URL, homeDirectory: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        return url.pathExtension == "app" && (parent == "/Applications"
            || parent == homeDirectory.appending(path: "Applications").standardizedFileURL.path)
    }

    /// Called on a utility queue, never the main actor. Only this installation's
    /// extension is retired; no NotificationCenter/chronod restart or cache purge.
    func repair() -> Bool {
        let retired = WidgetExtensionProcess.retire(executable: executableURL, owner: geteuid(),
            isRelocatedOwnWidget: { candidate in
                Self.isUpdaterStagingPath(candidate.executablePath)
                    && Self.hasWidgetSignature(pid: candidate.pid, team: teamIdentifier)
            })
        if retired > 0 {
            Log.app.notice("Retired previous UsageNow widget process after app replacement")
        }
        guard LSRegisterURL(appURL as CFURL, true) == noErr else { return false }
        return Self.registerExtension(at: extensionURL)
    }

    static func isUpdaterStagingPath(_ path: String) -> Bool {
        guard path.hasSuffix("/UsageNow.app/Contents/PlugIns/UsageNowWidget.appex/Contents/MacOS/UsageNowWidget") else { return false }
        let normalized = WidgetExtensionProcess.normalizedPath(path)
        let roots = [FileManager.default.temporaryDirectory,
                     URL(filePath: "/private/tmp"),
                     FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches/com.usagenow.UsageNow")]
        return roots.contains { normalized.hasPrefix(WidgetExtensionProcess.normalizedPath($0.path) + "/") }
    }

    /// A relocated executable needs an identity check, not just a familiar
    /// filename. The requirement verifies this product and this signing team.
    private static func hasWidgetSignature(pid: pid_t, team: String?) -> Bool {
        guard let team, team.count == 10, team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { return false }
        let rule = "anchor apple generic and identifier \"com.usagenow.UsageNow.Widget\" and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        var code: SecCode?
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code, let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func registerExtension(at url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pluginkit")
        process.arguments = ["-a", url.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return false }
        guard exited.wait(timeout: .now() + 5) == .success else {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL) // Only our own timed-out child.
            }
            return false
        }
        return process.terminationStatus == 0
    }
}

/// Process metadata only: no arguments, environment, provider files or memory.
/// Exact executable + owner + start time prevent killing similarly named apps,
/// widgets from a different installation, or a PID reused during the scan.
struct WidgetExtensionProcess: Sendable, Equatable {
    let pid: pid_t
    let owner: uid_t
    let executablePath: String
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64

    func belongs(to executable: URL, owner expectedOwner: uid_t) -> Bool {
        pid > 1 && pid != getpid() && owner == expectedOwner
            && Self.normalizedPath(executablePath) == Self.normalizedPath(executable.path)
    }

    static func normalizedPath(_ path: String) -> String {
        let value = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
        // Foundation shortens existing /private/tmp and /private/var roots,
        // but keeps /private on paths already removed by an installer.
        if value == "/private/tmp" || value == "/private/var"
            || value.hasPrefix("/private/tmp/") || value.hasPrefix("/private/var/") {
            return String(value.dropFirst("/private".count))
        }
        return value
    }

    @discardableResult
    static func retire(
        executable: URL,
        owner: uid_t,
        candidates: [Self] = currentUserProcesses(),
        inspect: (pid_t) -> Self? = read,
        terminate: (pid_t) -> Int32 = { kill($0, SIGTERM) },
        isRelocatedOwnWidget: (Self) -> Bool = { _ in false }
    ) -> Int {
        var retired = 0
        for candidate in candidates {
            guard candidate.pid > 1, candidate.pid != getpid(), candidate.owner == owner,
                  candidate.belongs(to: executable, owner: owner) || isRelocatedOwnWidget(candidate),
                  inspect(candidate.pid) == candidate else { continue }
            if terminate(candidate.pid) == 0 { retired += 1 }
        }
        return retired
    }

    static func currentUserProcesses() -> [Self] {
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), geteuid(), nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.stride + 32)
        let capacity = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let count = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), geteuid(), $0.baseAddress, capacity)
        }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count) / MemoryLayout<pid_t>.stride).compactMap(read)
    }

    static func read(_ pid: pid_t) -> Self? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
                == MemoryLayout<proc_bsdinfo>.size else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE is a C expression macro not imported by Swift.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        let executable: String
        if length > 0 {
            executable = String(decoding: path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        } else {
            // Sparkle may already have unlinked the old bundle. The kernel's
            // vnode path is then unavailable, but ps retains its launch path.
            // Ask only for comm (the executable), never args or environment.
            let name = withUnsafeBytes(of: info.pbi_name) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            guard let launchPath = deletedWidgetLaunchPath(pid: pid, owner: info.pbi_uid, name: name) else { return nil }
            executable = launchPath
        }
        return Self(pid: pid, owner: info.pbi_uid, executablePath: executable,
                    startedSeconds: info.pbi_start_tvsec, startedMicroseconds: info.pbi_start_tvusec)
    }

    static func deletedWidgetLaunchPath(
        pid: pid_t, owner: uid_t, name: String,
        lookup: (pid_t) -> String? = launchPath
    ) -> String? {
        guard owner == geteuid(), name == "UsageNowWidget", let path = lookup(pid),
              path.hasPrefix("/"), !path.contains("\n"),
              path.hasSuffix("/UsageNow.app/Contents/PlugIns/UsageNowWidget.appex/Contents/MacOS/UsageNowWidget") else { return nil }
        // retire() still requires this installation's exact path, process
        // owner and unchanged birth time before signalling the candidate.
        return path
    }

    private static func launchPath(_ pid: pid_t) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/bin/ps")
        process.arguments = ["-ww", "-p", String(pid), "-o", "comm="]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }
        guard exited.wait(timeout: .now() + 2) == .success else {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL) // Only our own child.
            }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
