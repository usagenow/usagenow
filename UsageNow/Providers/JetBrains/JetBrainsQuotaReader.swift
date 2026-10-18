import Foundation

enum JetBrainsQuotaReader {
    static let maxXMLBytes = 256 * 1_024
    static let maxLogBytes = 4 * 1_024 * 1_024

    struct Metadata {
        let size: Int
        let modifiedAt: Date?
    }

    static func metadata(_ url: URL) -> Metadata? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize else { return nil }
        return Metadata(size: size, modifiedAt: values.contentModificationDate)
    }

    static func read(_ installation: JetBrainsEnvironment.Installation, now: Date) -> JetBrainsQuota? {
        let xmlDate = installation.quotaModifiedAt
        let xml: JetBrainsQuota?
        if installation.hasQuotaFile, let xmlDate, xmlDate <= now,
           let bytes = readXML(installation.quotaFile) {
            xml = parseXML(bytes, observedAt: xmlDate)
        } else { xml = nil }

        // A log may replace XML only with evidence that it is fresher.
        guard !installation.hasQuotaFile || xmlDate != nil else { return xml }
        guard let logDate = installation.logModifiedAt, logDate <= now,
              let tail = readLogTail(installation.logFile),
              let log = JetBrainsQuotaLogParser.parse(tail, now: now),
              !installation.hasQuotaFile || log.observedAt > (xmlDate ?? .distantFuture) else { return xml }
        return log
    }

    static func readXML(_ url: URL) -> Data? {
        guard let info = metadata(url), info.size > 0, info.size <= maxXMLBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxXMLBytes + 1), data.count <= maxXMLBytes else { return nil }
        return data
    }

    /// Freeze the end offset: a growing log cannot turn this into an
    /// unbounded read. Discard a partial first line and reject an unfinished
    /// final record instead of resurrecting an older quota state.
    static func readLogTail(_ url: URL, maxBytes: Int = maxLogBytes) -> Data? {
        guard maxBytes > 0, metadata(url) != nil,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let count = Int(min(end, UInt64(maxBytes)))
        let start = end - UInt64(count)
        guard (try? handle.seek(toOffset: start)) != nil,
              var bytes = try? handle.read(upToCount: count), bytes.count == count,
              bytes.last == 0x0A else { return nil }
        if start > 0 {
            guard let newline = bytes.firstIndex(of: 0x0A) else { return nil }
            bytes.removeSubrange(...newline)
        }
        return bytes
    }

    static func parseXML(_ data: Data, observedAt: Date) -> JetBrainsQuota? {
        guard data.count <= maxXMLBytes, let text = String(data: data, encoding: .utf8),
              // Quota settings have no DTD. Reject it before XMLParser can
              // expand internal entities or encounter an external reference.
              !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else { return nil }
        let delegate = QuotaXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.ambiguous, let quotaJSON = delegate.values["quotaInfo"],
              let payload = try? JSONDecoder().decode(JetBrainsQuota.Payload.self, from: Data(quotaJSON.utf8)) else { return nil }

        struct Refill: Decodable { let type: String?; let next: String? }
        let refill = delegate.values["nextRefill"].flatMap { try? JSONDecoder().decode(Refill.self, from: Data($0.utf8)) }
        let reset = refill?.type == "Known" ? refill?.next.flatMap(JetBrainsQuota.date) : nil
        return payload.quota(observedAt: observedAt, reset: reset, allowsTotal: true)
    }

    private final class QuotaXMLDelegate: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        var ambiguous = false
        private var path: [String] = []
        private var isQuotaComponent = false
        private var seenComponent = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            path.append(name)
            if path == ["application", "component"], attributes["name"] == "AIAssistantQuotaManager2" {
                if seenComponent { ambiguous = true }
                seenComponent = true
                isQuotaComponent = true
            }
            guard isQuotaComponent, path == ["application", "component", "option"],
                  let key = attributes["name"], ["quotaInfo", "nextRefill"].contains(key),
                  let value = attributes["value"] else { return }
            if values[key] != nil { ambiguous = true }
            values[key] = value
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if path == ["application", "component"] { isQuotaComponent = false }
            path.removeLast()
        }
    }
}
