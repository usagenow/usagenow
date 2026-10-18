import Foundation
import Testing
@testable import UsageNow

private enum JBFixture {
    static let date = Date(timeIntervalSince1970: 1_792_238_400) // 2026-10-17 12:00 UTC
    static let monthly = #"{"type":"Available","current":"480","maximum":"1200","tariffQuota":{"current":"180","maximum":"600"},"topUpQuota":{"current":"300","maximum":"600","available":"300"},"until":"2027-10-01T00:00:00Z"}"#
    static let refill = #"{"type":"Known","next":"2026-11-01T12:30:15.125Z"}"#

    static func xml(_ quota: String = monthly, refill: String? = refill) -> Data {
        func escaped(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "\n", with: "&#10;") }
        return Data("""
            <application><component name="AIAssistantQuotaManager2">
            <option name="quotaInfo" value="\(escaped(quota))"/>
            \(refill.map { "<option name=\"nextRefill\" value=\"\(escaped($0))\"/>" } ?? "")
            </component></application>
            """.utf8)
    }

    static func log(_ body: String, at: String = "10:00:00,000", kind: String = "quota") -> String {
        let marker = kind == "junie"
            ? "AiaActivationTransmitter - Received message from junie: quota_update:"
            : "QuotaManager2Impl - New quota \(kind == "refill" ? "refill " : "")state is: "
        return "2026-10-17 \(at) [123] INFO - #test.\(marker)\(body)\n"
    }

    static let available = "Available(current=480, maximum=1200, until=2027-10-01T00:00:00Z, tariffQuota=QuotaDetails(current=180, maximum=600, available=420), topUpQuota=QuotaDetails(current=300, maximum=600, available=300))"

    static func parseLog(_ string: String) -> JetBrainsQuota? {
        JetBrainsQuotaLogParser.parse(Data(string.utf8), now: date, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    static func installation(_ directory: URL, xmlDate: Date? = date.addingTimeInterval(-86_400), hasXML: Bool = true) -> JetBrainsEnvironment.Installation {
        JetBrainsEnvironment.Installation(name: "IntelliJ IDEA 2026.2", quotaFile: directory.appending(path: "quota.xml"),
                                         logFile: directory.appending(path: "idea.log"), quotaModifiedAt: xmlDate,
                                         logModifiedAt: date, hasQuotaFile: hasXML)
    }
}

struct JetBrainsQuotaTests {
    @Test func monthlyPercentageExcludesTopUpsAndUsesActualRefill() throws {
        let quota = try #require(JetBrainsQuotaReader.parseXML(JBFixture.xml(), observedAt: JBFixture.date))
        #expect(quota.window.kind == .monthly)
        #expect(quota.window.usage?.remainingDisplayValue == 70)
        #expect(quota.window.resetsAt == JetBrainsQuota.date("2026-11-01T12:30:15.125Z"))
        #expect(quota.observedAt == JBFixture.date)
        #expect(quota.expiresAt != quota.window.resetsAt)
    }

    @Test func XMLHandlesEscapedNewlinesAndFlexibleNumbers() throws {
        let json = """
        {"type":"Available", "tariffQuota": {
          "current":{"amount":"2.5"},"maximum":10
        }}
        """
        let quota = try #require(JetBrainsQuotaReader.parseXML(JBFixture.xml(json), observedAt: JBFixture.date))
        #expect(quota.window.usage == UsagePercentage(percent: 25))
    }

    @Test(arguments: [#"{"current":"NaN","maximum":600}"#, #"{"current":20}"#, #"{"current":-20,"maximum":600}"#, "null"])
    func totalFallbackNeverMixesCountersOrInheritsMonthlyReset(tariff: String) throws {
        let data = JBFixture.xml("{\"current\":80,\"maximum\":400,\"tariffQuota\":\(tariff)}")
        let quota = try #require(JetBrainsQuotaReader.parseXML(data, observedAt: JBFixture.date))
        #expect(quota.window.kind == .allowance)
        #expect(quota.window.usage == UsagePercentage(percent: 20))
        #expect(quota.window.resetsAt == nil)
    }

    @Test(arguments: [#"{"type":"Unknown"}"#, #"{"type":"Error","current":1,"maximum":10}"#,
                      #"{"current":true,"maximum":10}"#, #"{"current":1,"maximum":0}"#,
                      #"{"current":-1,"maximum":10}"#, #"{"current":"Infinity","maximum":10}"#,
                      #"{"tariffQuota":{"current":1},"maximum":10}"#, #"{"current":1,"maximum":"1e-999"}"#])
    func unsupportedQuotaDoesNotInventAPercentage(json: String) {
        #expect(JetBrainsQuotaReader.parseXML(JBFixture.xml(json), observedAt: JBFixture.date) == nil)
    }

    @Test(arguments: [nil, #"{"type":"Error","next":"2026-11-01T00:00:00Z"}"#, #"{"type":"Known","next":"broken"}"#])
    func expiryNeverBecomesReset(refill: String?) throws {
        let quota = try #require(JetBrainsQuotaReader.parseXML(JBFixture.xml(refill: refill), observedAt: JBFixture.date))
        #expect(quota.window.resetsAt == nil)
        #expect(quota.expiresAt != nil)
    }

    @Test func expiredWindowsNeverBecomeFreshOrFull() throws {
        let quota = try #require(JetBrainsQuotaReader.parseXML(JBFixture.xml(), observedAt: JBFixture.date))
        #expect(quota.windows(at: JetBrainsQuota.date("2026-12-01T00:00:00Z")!).first?.usage == nil)
        let noReset = try #require(JetBrainsQuotaReader.parseXML(JBFixture.xml(refill: nil), observedAt: JBFixture.date))
        #expect(noReset.windows(at: JetBrainsQuota.date("2028-01-01T00:00:00Z")!).first?.usage == nil)
    }

    @Test func wrongComponentDuplicateOptionsMalformedXMLAndEntitiesAreRejected() {
        let valid = String(decoding: JBFixture.xml(), as: UTF8.self)
        for text in [valid.replacingOccurrences(of: "AIAssistantQuotaManager2", with: "OtherSettings"),
                     valid.replacingOccurrences(of: "</component>", with: "<option name=\"quotaInfo\" value=\"{}\"/></component>"),
                     String(valid.dropLast(5)),
                     "<!DOCTYPE application [<!ENTITY leak SYSTEM 'file:///not-to-be-read'>]>" + valid] {
            #expect(JetBrainsQuotaReader.parseXML(Data(text.utf8), observedAt: JBFixture.date) == nil)
        }
        #expect(JetBrainsQuotaReader.parseXML(Data(repeating: 32, count: JetBrainsQuotaReader.maxXMLBytes + 1), observedAt: JBFixture.date) == nil)
    }
}

struct JetBrainsLogTests {
    @Test func flatAndNestedQuotaFormats() throws {
        let nested = "Available(quota=JbaiQuota(license=IGNORED, quotaID=JbaiQuotaId(userId=null), tariffQuota=Details(current=180, maximum=600, available=420)))"
        for body in [JBFixture.available, nested] {
            let log = JBFixture.log(body) + JBFixture.log("Known(refill=JbaiQuotaRefill(tariff=JbaiQuotaTariff(amount=600, period=30d), next=2026-11-01T00:00:00Z))", at: "10:00:01,000", kind: "refill")
            let quota = try #require(JBFixture.parseLog(log))
            #expect(quota.window.usage?.remainingDisplayValue == 70)
            #expect(quota.window.resetsAt == JetBrainsQuota.date("2026-11-01T00:00:00Z"))
            #expect(quota.observedAt == JetBrainsQuota.date("2026-10-17T10:00:00Z"))
        }
    }

    @Test func junieHasNoRefillAndIgnoresOnlyTheMigrationError() throws {
        let junie = #"{"license":"DO-NOT-KEEP","quotaID":{"quotaId":"DO-NOT-KEEP"},"tariffQuota":{"current":{"amount":"90"},"maximum":{"amount":"600"}},"until":1822348800000}"#
        let migration = "Error(exception=com.intellij.ml.llm.core.AIAssistantForbiddenException: blocked (AirMigration))"
        let log = JBFixture.log(JBFixture.available)
            + JBFixture.log("Known(next=2026-11-01T00:00:00Z)", at: "10:00:01,000", kind: "refill")
            + JBFixture.log(junie, at: "10:01:00,000", kind: "junie")
            + JBFixture.log(migration, at: "10:01:01,000")
            + JBFixture.log("Known(next=2026-11-01T00:00:00Z)", at: "10:01:02,000", kind: "refill")
        let quota = try #require(JBFixture.parseLog(log))
        #expect(quota.window.usage?.remainingDisplayValue == 85)
        #expect(quota.window.resetsAt == nil)
        #expect(!String(describing: quota).contains("DO-NOT-KEEP"))
    }

    @Test(arguments: ["Unknown", "Error(exception=PermissionDenied)", "Available(tariffQuota=Details(current=NaN, maximum=100))",
                      "Available(tariffQuota=Details(current=1, maximum=100)", "Available(quota=ChangedFormat(current=1, maximum=100))"])
    func latestInvalidStateDiscardsPreviousSuccess(body: String) {
        #expect(JBFixture.parseLog(JBFixture.log(JBFixture.available) + JBFixture.log(body, at: "10:01:00,000")) == nil)
    }

    @Test func invalidJunieInvalidatesOlderQuota() {
        #expect(JBFixture.parseLog(JBFixture.log(JBFixture.available) + JBFixture.log("{}", at: "10:01:00,000", kind: "junie")) == nil)
    }

    @Test func unrelatedTextAndFutureOrPartialRecordsAreNotReadAsQuota() {
        #expect(JBFixture.parseLog("Unrelated message about Available(current=0,maximum=100)\n") == nil)
        #expect(JBFixture.parseLog(JBFixture.log(JBFixture.available, at: "23:59:59,000")) == nil)
        #expect(JBFixture.parseLog(String(JBFixture.log(JBFixture.available).dropLast())) == nil)
        #expect(JBFixture.parseLog(JBFixture.log(JBFixture.available) + "unfinished") == nil)
    }

    @Test func newQuotaCannotBorrowAnEarlierRefill() throws {
        let log = JBFixture.log(JBFixture.available)
            + JBFixture.log("Known(next=2026-11-01T00:00:00Z)", at: "10:00:01,000", kind: "refill")
            + JBFixture.log(JBFixture.available, at: "10:01:00,000")
        #expect(try #require(JBFixture.parseLog(log)).window.resetsAt == nil)
    }

    @Test func quotedQuotaMarkerInAnUnrelatedMessageIsIgnored() throws {
        let fake = "2026-10-17 10:01:00,000 [123] INFO - #other.Logger - QuotaManager2Impl - New quota state is: Unknown\n"
        #expect(try #require(JBFixture.parseLog(JBFixture.log(JBFixture.available) + fake)).window.usage?.remainingDisplayValue == 70)
    }

    @Test func malformedRefillClearsResetButNeverFreshensQuota() throws {
        let log = JBFixture.log(JBFixture.available)
            + JBFixture.log("Known(next=2026-11-01T00:00:00Z)", at: "10:01:00,000", kind: "refill")
            + JBFixture.log("Error(exception=Offline)", at: "10:02:00,000", kind: "refill")
        let quota = try #require(JBFixture.parseLog(log))
        #expect(quota.window.resetsAt == nil)
        #expect(quota.observedAt == JetBrainsQuota.date("2026-10-17T10:00:00Z"))
    }
}

struct JetBrainsFileTests {
    @Test func newestQuotaXMLSelectsOneIDEAndNeverBorrowsAnotherLog() throws {
        let directory = try TemporaryDirectory()
        let config = directory.url.appending(path: "Library/Application Support/JetBrains")
        let first = config.appending(path: "IntelliJIdea2026.2/options")
        let second = config.appending(path: "PyCharm2026.2/options")
        let otherLog = directory.url.appending(path: "Library/Logs/JetBrains/PyCharm2026.2")
        for path in [first, second, otherLog] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        let a = first.appending(path: "AIAssistantQuotaManager2.xml")
        let b = second.appending(path: "AIAssistantQuotaManager2.xml")
        try JBFixture.xml().write(to: a)
        try JBFixture.xml(#"{"current":99,"maximum":100}"#).write(to: b)
        try Data(JBFixture.log(JBFixture.available).utf8).write(to: otherLog.appending(path: "idea.log"))
        try FileManager.default.setAttributes([.modificationDate: JBFixture.date.addingTimeInterval(-3600)], ofItemAtPath: a.path)
        try FileManager.default.setAttributes([.modificationDate: JBFixture.date.addingTimeInterval(-7200)], ofItemAtPath: b.path)
        let selected = try #require(JetBrainsEnvironment.discover(homeDirectory: directory.url).selected)
        #expect(selected.name == "IntelliJ IDEA 2026.2")
        let quota = try #require(JetBrainsQuotaReader.read(selected, now: JBFixture.date))
        #expect(quota.window.usage?.remainingDisplayValue == 70)
        #expect(quota.window.resetsAt != nil, "Another IDE's log cannot replace this XML")
    }

    @Test func newerLogReplacesQuotaAndResetTogether() throws {
        let directory = try TemporaryDirectory()
        let source = JBFixture.installation(directory.url)
        try JBFixture.xml().write(to: source.quotaFile)
        try Data(JBFixture.log(JBFixture.available).utf8).write(to: source.logFile)
        let quota = try #require(JetBrainsQuotaReader.read(source, now: JBFixture.date))
        #expect(quota.observedAt > source.quotaModifiedAt!)
        #expect(quota.window.resetsAt == nil)
    }

    @Test func unknownXMLDateOrOlderLogCannotReplaceXML() throws {
        let directory = try TemporaryDirectory()
        let source = JBFixture.installation(directory.url, xmlDate: JBFixture.date)
        try JBFixture.xml().write(to: source.quotaFile)
        try Data(JBFixture.log(JBFixture.available).utf8).write(to: source.logFile)
        #expect(JetBrainsQuotaReader.read(source, now: JBFixture.date)?.observedAt == JBFixture.date)
        #expect(JetBrainsQuotaReader.read(JBFixture.installation(directory.url, xmlDate: nil), now: JBFixture.date) == nil)
    }

    @Test func malformedNewestLogFallsBackToXML() throws {
        let directory = try TemporaryDirectory()
        let source = JBFixture.installation(directory.url)
        try JBFixture.xml().write(to: source.quotaFile)
        try Data((JBFixture.log(JBFixture.available) + JBFixture.log("Unknown", at: "10:01:00,000")).utf8).write(to: source.logFile)
        #expect(JetBrainsQuotaReader.read(source, now: JBFixture.date)?.observedAt == source.quotaModifiedAt)
    }

    @Test func boundedTailDropsPartialFirstLineAndRejectsUnfinishedLastLine() throws {
        let directory = try TemporaryDirectory()
        let log = directory.url.appending(path: "idea.log")
        try Data("cut line\nwhole line\n".utf8).write(to: log)
        #expect(JetBrainsQuotaReader.readLogTail(log, maxBytes: 15) == Data("whole line\n".utf8))
        try Data("cut line\nwhole line\nunfinished".utf8).write(to: log)
        #expect(JetBrainsQuotaReader.readLogTail(log, maxBytes: 15) == nil)
    }

    @Test func ignoresSymlinksAndOversizedXML() throws {
        let directory = try TemporaryDirectory()
        let actual = directory.url.appending(path: "actual.xml")
        let link = directory.url.appending(path: "quota.xml")
        try JBFixture.xml().write(to: actual)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
        #expect(JetBrainsQuotaReader.readXML(link) == nil)
        try Data(repeating: 32, count: JetBrainsQuotaReader.maxXMLBytes + 1).write(to: actual)
        #expect(JetBrainsQuotaReader.readXML(actual) == nil)
    }

    @Test func detectsAndroidStudioButNotArbitraryFolders() {
        #expect(JetBrainsEnvironment.displayName(folder: "AndroidStudio2026.2", vendor: "Google") == "Android Studio 2026.2")
        #expect(JetBrainsEnvironment.displayName(folder: "PyCharmCE2026.1", vendor: "JetBrains") == "PyCharm Community 2026.1")
        for folder in ["Daemon", "consentOptions", "account@example.com", "IntelliJIdea2026.2/private", "Other2026.1"] {
            #expect(JetBrainsEnvironment.displayName(folder: folder, vendor: "JetBrains") == nil)
        }
    }

    @Test func detectsLogOnlyInstallationWithoutReadingPromptsOrAccounts() throws {
        let directory = try TemporaryDirectory()
        let logs = directory.url.appending(path: "Library/Logs/Google/AndroidStudio2026.2")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appending(path: "idea.log")
        try Data(JBFixture.log(JBFixture.available).utf8).write(to: log)
        try FileManager.default.setAttributes([.modificationDate: JBFixture.date], ofItemAtPath: log.path)
        let selected = try #require(JetBrainsEnvironment.discover(homeDirectory: directory.url).selected)
        #expect(!selected.hasQuotaFile)
        #expect(JetBrainsQuotaReader.read(selected, now: JBFixture.date) != nil)
    }
}

struct JetBrainsProviderTests {
    @MainActor @Test func disabledProviderNeverDiscoversOrReadsFiles() async {
        let provider = JetBrainsProvider(discover: {
            Issue.record("Disabled JetBrains must not inspect the filesystem")
            return JetBrainsEnvironment(installations: [])
        })
        let store = UsageStore(providers: [provider], enabledProviders: [])
        await store.refresh()
        #expect(store.snapshots.isEmpty)
    }

    @Test func cachedReadKeepsItsRealAgeAndInventsNoPlanActivityOrCreditConversion() async throws {
        let old = JBFixture.date.addingTimeInterval(-3600)
        let quota = try #require(JetBrainsQuotaReader.parseXML(JBFixture.xml(), observedAt: old))
        let provider = JetBrainsProvider(
            discover: { JetBrainsEnvironment(installations: [JBFixture.installation(URL(filePath: "/nonexistent"))]) },
            read: { _, _ in quota }, now: { JBFixture.date }
        )
        let snapshot = try await provider.fetchSnapshot(trigger: .manual)
        #expect(snapshot.status == .available)
        #expect(snapshot.isStale(at: JBFixture.date))
        #expect(snapshot.dataDate == old)
        #expect(snapshot.activity == .unknown)
        #expect(snapshot.planName == nil && snapshot.totals.isEmpty && snapshot.balance == nil)
        #expect(snapshot.sourceLabel == "IntelliJ IDEA 2026.2")
        #expect(MenuBarDisplayMode.jetbrainsPercentage.usage(in: [snapshot])?.remainingDisplayValue == 70)
    }

    @Test func missingCacheHasAnActionableHintNotAFabricatedLimit() async throws {
        let provider = JetBrainsProvider(
            discover: { JetBrainsEnvironment(installations: [JBFixture.installation(URL(filePath: "/nonexistent"))]) },
            read: { _, _ in nil }, now: { JBFixture.date }
        )
        let snapshot = try await provider.fetchSnapshot(trigger: .manual)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.quotaUnavailableReason == .toolNotRunning)
        #expect(snapshot.quotaUnavailableReason?.message(for: .jetbrains).contains("AI Assistant") == true)
    }

    @Test func absentIDEIsHidden() async throws {
        let provider = JetBrainsProvider(discover: { JetBrainsEnvironment(installations: []) })
        #expect(try await provider.fetchSnapshot(trigger: .manual).status == .notInstalled)
    }

    @MainActor @Test func widgetReceivesOnlySanitizedQuotaAndOriginalDate() throws {
        let quota = try #require(JetBrainsQuotaReader.parseXML(JBFixture.xml(), observedAt: JBFixture.date.addingTimeInterval(-3600)))
        let snapshot = ProviderSnapshot(provider: .jetbrains, status: .available, windows: [quota.window],
                                        updatedAt: JBFixture.date, limitsUpdatedAt: quota.observedAt, sourceLabel: "IntelliJ IDEA 2026.2")
        let widget = WidgetSnapshotWriter.makeSnapshot(states: [ProviderState(provider: .jetbrains, snapshot: snapshot)],
                                                      enabledProviders: [.jetbrains], generatedAt: JBFixture.date)
        #expect(widget.providers.first?.provider == .jetbrains)
        #expect(widget.providers.first?.updatedAt == quota.observedAt)
        let encoded = String(decoding: try JSONEncoder().encode(widget), as: UTF8.self)
        #expect(!encoded.contains("IntelliJ") && !encoded.contains("quotaFile") && !encoded.contains("license"))
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: Data(encoded.utf8)) == widget)
        #expect(TelemetryEvent.detected(.jetbrains) == nil, "No telemetry schema expansion in this integration")
    }
}
