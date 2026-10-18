import Foundation

/// An allowlisted reader of quota events, not a general IDE log importer.
/// All raw strings live only for this parse; no log lines are saved or logged.
enum JetBrainsQuotaLogParser {
    private static let assistant = "QuotaManager2Impl - New quota state is: "
    private static let refill = "QuotaManager2Impl - New quota refill state is: "
    private static let junie = "AiaActivationTransmitter - Received message from junie: quota_update:"

    static func parse(_ data: Data, now: Date, timeZone: TimeZone = .autoupdatingCurrent) -> JetBrainsQuota? {
        guard data.count <= JetBrainsQuotaReader.maxLogBytes, data.last == 0x0A else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        formatter.isLenient = false
        var latest: JetBrainsQuota?
        var acceptsRefill = false
        var latestEventAt = Date.distantPast
        let markers = [assistant, refill, junie].map { ($0, Data($0.utf8)) }

        for bytes in data.split(separator: 0x0A) {
            let lineData = Data(bytes)
            guard let marker = markers.first(where: { lineData.contains($0.1) })?.0 else { continue }
            // An oversized quota line is a changed format, not permission
            // to keep showing an earlier successful event.
            guard bytes.count <= 64 * 1_024, let line = String(data: lineData, encoding: .utf8),
                  let range = line.range(of: marker) else { latest = nil; acceptsRefill = false; continue }
            // A quoted marker in another logger's message is not a quota
            // event. Require the IDE's logger header, not a substring hit.
            let prefix = String(line[..<range.lowerBound])
            guard prefix.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}\s+\[\s*\d+\]\s+(?:INFO|WARN|ERROR|DEBUG)\s+-\s+#?[A-Za-z0-9_.$]*$"#, options: .regularExpression) != nil else { continue }
            let body = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if marker == assistant, body.hasPrefix("Error("),
               body.contains("AIAssistantForbiddenException"), body.contains("(AirMigration)") { continue }

            guard let date = formatter.date(from: String(line.prefix(23))), date <= now, date >= latestEventAt else {
                latest = nil; acceptsRefill = false; continue
            }
            latestEventAt = date
            if marker == refill {
                guard acceptsRefill, let quota = latest else { continue }
                let fields = fields(body, names: ["Known"])
                let values = fields?["refill"].flatMap { self.fields($0, names: ["JbaiQuotaRefill"]) } ?? fields
                let reset = values?["next"].flatMap(JetBrainsQuota.date)
                latest = JetBrainsQuota(
                    window: UsageWindow(kind: quota.window.kind, usage: quota.window.usage, resetsAt: reset),
                    expiresAt: quota.expiresAt, observedAt: quota.observedAt
                )
                continue
            }

            latest = nil
            acceptsRefill = false
            if marker == junie {
                if let payload = try? JSONDecoder().decode(JetBrainsQuota.Payload.self, from: Data(body.utf8)) {
                    latest = payload.quota(observedAt: date, reset: nil, allowsTotal: false)
                }
            } else if let available = fields(body, names: ["Available"]) {
                let quota = available["quota"].flatMap { fields($0, names: ["JbaiQuota"]) } ?? available
                guard let tariff = quota["tariffQuota"].flatMap({ fields($0, names: ["QuotaDetails", "Details"]) }),
                      let used = tariff["current"].flatMap(Double.init),
                      let maximum = tariff["maximum"].flatMap(Double.init),
                      let usage = JetBrainsQuota.percentage(used: used, total: maximum) else { continue }
                latest = JetBrainsQuota(window: UsageWindow(kind: .monthly, usage: usage, resetsAt: nil),
                                        expiresAt: quota["until"].flatMap(JetBrainsQuota.date), observedAt: date)
                acceptsRefill = true
            }
        }
        return latest
    }

    /// Split a Kotlin-style value at its own commas, never inside nested
    /// groups. Only explicitly requested numeric/date fields are decoded.
    private static func fields(_ text: String, names: Set<String>) -> [String: String]? {
        guard let open = text.firstIndex(of: "("), names.contains(String(text[..<open])), text.last == ")" else { return nil }
        let body = text[text.index(after: open)..<text.index(before: text.endIndex)]
        var depth = 0
        var start = body.startIndex
        var parts: [Substring] = []
        for index in body.indices {
            switch body[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "," where depth == 0:
                parts.append(body[start..<index]); start = body.index(after: index)
            default: break
            }
            guard depth >= 0, depth <= 8 else { return nil }
        }
        guard depth == 0 else { return nil }
        parts.append(body[start...])
        var result: [String: String] = [:]
        for part in parts {
            guard let equal = part.firstIndex(of: "=") else { return nil }
            let key = part[..<equal].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, result[key] == nil else { return nil }
            result[key] = part[part.index(after: equal)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
