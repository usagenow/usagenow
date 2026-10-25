import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let app = Bundle(url: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(("usagenow: \(message)\n").utf8))
    exit(code)
}
switch arguments {
case [], ["--help"], ["help"]:
    print("""
    Usage: usagenow status [--json]
           usagenow --version

    Reads the latest safe snapshot written by UsageNow. Does not refresh providers.
    Open UsageNow to update data. STALE values are last known readings.
    Exit codes: 0 success (including stale/empty); 1 snapshot unavailable; 2 invalid arguments.
    JSON schema version: 1. All dates use ISO 8601 UTC; percentages mean remaining.
    """)
case ["--version"]:
    print("UsageNow \(app?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
case ["status"], ["status", "--json"]:
    guard let group = app?.object(forInfoDictionaryKey: "UsageNowAppGroupIdentifier") as? String,
          !group.contains("/"), !group.isEmpty else { fail("run the command bundled with UsageNow.", code: 1) }
    let file = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Group Containers").appending(path: group).appending(path: "widget-snapshot.json")
    guard let reader = try? FileHandle(forReadingFrom: file) else {
        fail("snapshot unavailable. Open UsageNow to create it.", code: 1)
    }
    defer { try? reader.close() }
    // Bound the allocation before decoding even if the snapshot is malformed.
    let maximumBytes = 4 * 1024 * 1024
    guard let data = try? reader.read(upToCount: maximumBytes + 1), data.count <= maximumBytes else {
        fail("snapshot unreadable or too large. Open UsageNow to update it.", code: 1)
    }
    do {
        let status = try CLIStatus.read(data, now: .now)
        print(arguments.contains("--json") ? try status.json() : status.text)
    } catch { fail("snapshot unreadable or unsupported. Open UsageNow to update it.", code: 1) }
default: fail("unknown arguments. Use --help.", code: 2)
}
