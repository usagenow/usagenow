import CryptoKit
import Foundation

/// A 429 pauses this credential at this host, not unrelated accounts.
/// Shared by background refresh, manual refresh, and connection checks.
/// Only an ephemeral keyed fingerprint and a deadline are retained. Neither
/// credentials nor fingerprints are logged, persisted, or sent anywhere.
actor APIRequestCooldown {
    static let shared = APIRequestCooldown()
    private struct Connection: Hashable {
        let host: String
        let fingerprint: Data
    }
    private let salt = SymmetricKey(size: .bits256)
    private var deadlines: [Connection: Date] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { .now }) { self.now = now }

    func check(host: String, credential: String) throws {
        let date = now()
        deadlines = deadlines.filter { $0.value > date }
        if let until = deadlines[connection(host: host, credential: credential)] {
            throw APIKeyClient.Failure.rateLimited(until: until)
        }
    }

    func record(host: String, credential: String, retryAfter: String?) -> Date {
        let date = now()
        deadlines = deadlines.filter { $0.value > date }
        let key = connection(host: host, credential: credential)
        // Another in-flight response must not shorten an existing pause.
        let until = max(deadlines[key] ?? date, RetryAfter.deadline(retryAfter, now: date))
        deadlines[key] = until
        return until
    }

    private func connection(host: String, credential: String) -> Connection {
        Connection(host: host, fingerprint: Data(HMAC<SHA256>.authenticationCode(for: Data(credential.utf8), using: salt)))
    }
}

enum RetryAfter {
    static let fallbackDelay: TimeInterval = 5 * 60

    /// RFC 9110: a non-negative integer number of seconds or an HTTP date.
    /// Missing, malformed, past, or unrepresentable dates use five minutes.
    static func deadline(_ header: String?, now: Date) -> Date {
        let fallback = now.addingTimeInterval(fallbackDelay)
        guard let value = header?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.utf8.count <= 128 else { return fallback }
        if value.utf8.allSatisfy({ (48...57).contains($0) }), let seconds = TimeInterval(value),
           seconds.isFinite, seconds < 253_402_300_799 - now.timeIntervalSince1970 {
            return now.addingTimeInterval(max(1, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value), date > now { return date }
        }
        return fallback
    }
}
