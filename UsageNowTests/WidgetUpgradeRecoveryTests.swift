import Darwin
import Foundation
import SwiftUI
import Testing
@testable import UsageNow

@MainActor
struct WidgetUpgradeRecoveryTests {
    private func installation(build: String = "17", path: String = "/Applications/UsageNow.app") -> WidgetInstallation {
        let app = URL(filePath: path)
        let widget = app.appending(path: "Contents/PlugIns/UsageNowWidget.appex")
        return .init(appURL: app, extensionURL: widget,
                     executableURL: widget.appending(path: "Contents/MacOS/UsageNowWidget"), build: build)
    }

    @Test func upgradingRepairsOnceAndAnOrdinaryRelaunchDoesNotRestartTheWidget() async {
        let suite = "WidgetUpgradeRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var repairs = 0
        var reloads = 0
        var pauses = 0
        let repair: (WidgetInstallation) async -> Bool = { _ in repairs += 1; return true }
        let reload: () -> Void = { reloads += 1 }
        let pause: () async -> Void = { pauses += 1 }
        let recovery = WidgetUpgradeRecovery(defaults: defaults)
        await recovery.recover(installation: installation(), repair: repair, reload: reload, pause: pause)
        #expect(repairs == 1 && reloads == 2 && pauses == 2)
        // A newly constructed coordinator represents the next app launch.
        await WidgetUpgradeRecovery(defaults: defaults).recover(
            installation: installation(), repair: repair, reload: reload, pause: pause)
        #expect(repairs == 1 && reloads == 2)
        await recovery.recover(installation: installation(build: "18"), repair: repair, reload: reload, pause: pause)
        #expect(repairs == 2 && reloads == 4)
    }

    @Test func aFailedRegistrationCanRetryAndDoesNotReloadAnInvalidExtension() async {
        let suite = "WidgetUpgradeRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recovery = WidgetUpgradeRecovery(defaults: defaults)
        await recovery.recover(installation: installation(), repair: { _ in false },
            reload: { Issue.record("Failed registration must not be treated as success") }, pause: {})
        #expect(defaults.string(forKey: WidgetUpgradeRecovery.completedBuildKey) == nil)
        var reloaded = false
        await recovery.recover(installation: installation(), repair: { _ in true }, reload: { reloaded = true }, pause: {})
        #expect(reloaded)
        #expect(defaults.string(forKey: WidgetUpgradeRecovery.completedBuildKey) == installation().key)
    }

    @Test func developmentArchiveAndDiskImageCopiesCannotTakeOverRegistration() {
        let home = URL(filePath: "/Users/example")
        #expect(WidgetInstallation.isInstalledApp(URL(filePath: "/Applications/UsageNow.app"), homeDirectory: home))
        #expect(WidgetInstallation.isInstalledApp(home.appending(path: "Applications/UsageNow.app"), homeDirectory: home))
        for path in ["/tmp/export/UsageNow.app", "/Volumes/UsageNow/UsageNow.app",
                     "/Users/example/project/build/UsageNow.app", "/ApplicationsExtra/UsageNow.app"] {
            #expect(!WidgetInstallation.isInstalledApp(URL(filePath: path), homeDirectory: home))
        }
        #expect(WidgetInstallation(bundle: .main) == nil, "The Debug test host must never repair the installed widget")
    }

    @Test func retirementTargetsOnlyThisInstallAndRechecksPIDIdentity() {
        let executable = installation().executableURL
        let owner = geteuid()
        func process(_ pid: pid_t, path: String? = nil, uid: uid_t? = nil, start: UInt64 = 10) -> WidgetExtensionProcess {
            .init(pid: pid, owner: uid ?? owner, executablePath: path ?? executable.path,
                  startedSeconds: start, startedMicroseconds: 0)
        }
        let own = process(1001)
        let reused = process(1002)
        let anotherUser = process(1003, uid: owner + 1)
        let anotherInstall = process(1004, path: "/tmp/UsageNow.app/Contents/PlugIns/UsageNowWidget.appex/Contents/MacOS/UsageNowWidget")
        let unrelated = process(1005, path: "/System/Library/CoreServices/NotificationCenter.app/Contents/MacOS/NotificationCenter")
        var terminated: [pid_t] = []
        let count = WidgetExtensionProcess.retire(executable: executable, owner: owner,
            candidates: [own, reused, anotherUser, anotherInstall, unrelated, process(getpid())],
            inspect: { pid in pid == reused.pid ? process(pid, start: 20) : own },
            terminate: { terminated.append($0); return 0 })
        #expect(count == 1)
        #expect(terminated == [own.pid])
    }

    @Test func processMetadataCanIdentifyTheCurrentProcessWithoutReadingArguments() throws {
        let current = try #require(WidgetExtensionProcess.read(getpid()))
        #expect(current.owner == geteuid())
        #expect(!current.executablePath.isEmpty)
        #expect(current.startedSeconds > 0)
        #expect(WidgetExtensionProcess.currentUserProcesses().contains { $0.pid == getpid() })
    }

    @Test func retirementEndsOnlyTheOwnedFixtureProcess() async throws {
        let executable = URL(filePath: "/bin/sleep")
        let fixture = Process()
        fixture.executableURL = executable
        fixture.arguments = ["30"]
        fixture.environment = ["PATH": "/usr/bin:/bin"]
        let unrelated = Process()
        unrelated.executableURL = URL(filePath: "/usr/bin/tail")
        unrelated.arguments = ["-f", "/dev/null"]
        unrelated.environment = ["PATH": "/usr/bin:/bin"]
        defer {
            if fixture.isRunning { fixture.terminate() }
            if unrelated.isRunning { unrelated.terminate() }
        }
        try fixture.run()
        try unrelated.run()
        for _ in 0..<50 {
            if WidgetExtensionProcess.read(fixture.processIdentifier)?.executablePath == executable.resolvingSymlinksInPath().path { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let own = try #require(WidgetExtensionProcess.read(fixture.processIdentifier))
        let other = try #require(WidgetExtensionProcess.read(unrelated.processIdentifier))
        let retired = WidgetExtensionProcess.retire(executable: executable, owner: geteuid(), candidates: [own, other])
        for _ in 0..<50 where fixture.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        #expect(retired == 1, "Candidate: \(own); target: \(executable.resolvingSymlinksInPath().path); current: \(String(describing: WidgetExtensionProcess.read(fixture.processIdentifier)))")
        #expect(!fixture.isRunning)
        #expect(unrelated.isRunning)
    }

    @Test func relocatedProcessesRequireExplicitIdentityValidation() {
        let executable = installation().executableURL
        let path = "/private/tmp/installer/UsageNow.app/Contents/PlugIns/UsageNowWidget.appex/Contents/MacOS/UsageNowWidget"
        let moved = WidgetExtensionProcess(pid: 1001, owner: geteuid(), executablePath: path, startedSeconds: 10, startedMicroseconds: 0)
        #expect(WidgetInstallation.isUpdaterStagingPath(path))
        #expect(WidgetInstallation.isUpdaterStagingPath(String(path.dropFirst("/private".count))))
        #expect(!WidgetInstallation.isUpdaterStagingPath(path.replacingOccurrences(of: "/private/tmp/", with: "/private/tmp-other/")))
        #expect(!WidgetInstallation.isUpdaterStagingPath("/Applications/Other.app/Contents/PlugIns/UsageNowWidget.appex/Contents/MacOS/UsageNowWidget"))
        var signaled = false
        WidgetExtensionProcess.retire(executable: executable, owner: geteuid(), candidates: [moved],
            inspect: { _ in moved }, terminate: { _ in signaled = true; return 0 })
        #expect(!signaled, "A matching filename is not proof of ownership")
        WidgetExtensionProcess.retire(executable: executable, owner: geteuid(), candidates: [moved],
            inspect: { _ in moved }, terminate: { _ in signaled = true; return 0 }, isRelocatedOwnWidget: { _ in true })
        #expect(signaled)
    }

    @Test func staleAgeAdvancesAtMinutePrecisionBetweenTimelineReloads() {
        let recorded = TestDates.noon
        let format = WidgetUpdatedLabel.ageFormat(since: recorded).locale(Locale(identifier: "en_US"))
        let ten = String(format.format(recorded.addingTimeInterval(600)).characters)
        let forty = String(format.format(recorded.addingTimeInterval(2400)).characters)
        #expect(ten.contains("10") && forty.contains("40"))
        #expect(ten != forty)
        #expect(format.format(recorded.addingTimeInterval(601)) == format.format(recorded.addingTimeInterval(602)),
                "No per-second redraw or provider requests are needed")
    }

    @Test func deletedExecutableFallbackIsLimitedToOurOwnedWidget() {
        let path = installation().executableURL.path
        let owner = geteuid()
        var lookups = 0
        let lookup: (pid_t) -> String? = { _ in lookups += 1; return path }
        #expect(WidgetExtensionProcess.deletedWidgetLaunchPath(pid: 1001, owner: owner,
            name: "UsageNowWidget", lookup: lookup) == path)
        #expect(WidgetExtensionProcess.deletedWidgetLaunchPath(pid: 1001, owner: owner + 1,
            name: "UsageNowWidget", lookup: lookup) == nil)
        #expect(WidgetExtensionProcess.deletedWidgetLaunchPath(pid: 1001, owner: owner,
            name: "NotificationCenter", lookup: lookup) == nil)
        #expect(lookups == 1)
        for invalid in ["UsageNowWidget", "/tmp/UsageNowWidget", path + "\n/bin/sleep", ""] {
            #expect(WidgetExtensionProcess.deletedWidgetLaunchPath(pid: 1001, owner: owner,
                name: "UsageNowWidget", lookup: { _ in invalid }) == nil)
        }
    }
}
