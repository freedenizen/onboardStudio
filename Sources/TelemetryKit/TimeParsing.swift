import Foundation

/// Parsers for the time formats found in data-logger files.
public enum TimeParsing {
    /// Parses `hh:mm:ss.nn`, `mm:ss.nn`, or plain seconds into seconds. Returns `nil` on failure.
    public static func seconds(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(":") {
            return Double(trimmed.replacingOccurrences(of: ",", with: "."))
        }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Formats seconds as `m:ss.hh` (or `h:mm:ss.hh` when an hour or longer).
    public static func lapTimeString(_ seconds: Double) -> String {
        // Clamp to under 100 hours so garbage values format instead of trapping on Int().
        let total = seconds.isFinite ? min(max(0, seconds), 359_999.99) : 0
        let hours = Int(total / 3600)
        let minutes = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = total.truncatingRemainder(dividingBy: 60)
        if hours > 0 {
            return String(format: "%d:%02d:%05.2f", hours, minutes, secs)
        }
        return String(format: "%d:%05.2f", minutes, secs)
    }
}
